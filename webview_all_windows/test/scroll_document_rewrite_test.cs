// Compiled and run by scroll_document_rewrite_test.ps1 with the WebView2 SDK.
using System;
using System.Collections.Generic;
using System.IO;
using System.Web.Script.Serialization;
using System.Windows.Forms;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;

internal sealed class ScrollRewriteTest : Form {
  private readonly WebView2 view = new WebView2();
  private readonly string source;
  private readonly JavaScriptSerializer json = new JavaScriptSerializer();
  private readonly List<double> positions = new List<double>();
  private bool started;
  private int checks;

  private ScrollRewriteTest(string source) {
    this.source = source;
    ClientSize = new System.Drawing.Size(800, 600);
    ShowInTaskbar = false;
    view.Dock = DockStyle.Fill;
    Controls.Add(view);
    Shown += Start;
    var timeout = new Timer { Interval = 20000 };
    timeout.Tick += delegate { Fail("WebView2 test timed out"); };
    timeout.Start();
  }

  private async void Start(object sender, EventArgs args) {
    try {
      await view.EnsureCoreWebView2Async();
      view.CoreWebView2.WebMessageReceived += Receive;
      view.CoreWebView2.NavigationCompleted += RunStages;
      await view.CoreWebView2.AddScriptToExecuteOnDocumentCreatedAsync(source);
      view.CoreWebView2.NavigateToString("<html><body style='height:5000px'>Initial document</body></html>");
    } catch (Exception error) { Fail(error.ToString()); }
  }

  private async void RunStages(object sender, CoreWebView2NavigationCompletedEventArgs args) {
    if (started) { return; }
    started = true;
    string script = @"
      (async function() {
        const source = SOURCE;
        const settle = () => new Promise(resolve => setTimeout(resolve, 100));
        function check(label, y, exactCount) {
          window.chrome.webview.postMessage({check: label, y: y, exactCount: exactCount,
            actualY: window.scrollY, installed: window.__flutterWindowsScrollHookInstalled,
            height: document.documentElement.scrollHeight, viewport: window.innerHeight});
        }
        await settle();
        window.scrollTo(0, 120);
        await settle();
        check('initial scroll', 120, null);

        document.open();
        document.write('<html><body style=""height:5000px"">First replacement</body></html>');
        // Leave this rewrite open to verify recovery without document.close().
        // Scroll before the observer runs: recovery must report this position.
        window.scrollTo(0, 240);
        await settle();
        check('scroll during document rewrite', 240, null);

        window.dispatchEvent(new Event('scroll'));
        window.dispatchEvent(new Event('scroll'));
        check('ordinary equal-position events remain observable', 240, 2);

        const root = document.documentElement;
        root.replaceWith(root.cloneNode(true));
        window.scrollTo(0, 360);
        await settle();
        check('root replacement', 360, null);

        (0, eval)(source);
        (0, eval)(source);
        window.dispatchEvent(new Event('scroll'));
        check('repeated injection does not duplicate listeners', 360, 1);

        document.open();
        document.write('<html><body style=""height:100px"">Second replacement</body></html>');
        document.close();
        await settle();
        check('rewrite reset is reported', 0, null);
        document.body.style.height = '5000px';
        window.scrollTo(0, 480);
        await settle();
        check('scroll after second rewrite', 480, null);

        document.body.appendChild(document.createElement('div'));
        await settle();
        window.dispatchEvent(new Event('scroll'));
        check('body mutations do not add listeners', 480, 1);
        window.chrome.webview.postMessage({complete: true});
      })().catch(function(error) {
        window.chrome.webview.postMessage({failure: String(error)});
      });
    ";
    try { await view.CoreWebView2.ExecuteScriptAsync(script.Replace("SOURCE", json.Serialize(source))); }
    catch (Exception error) { Fail(error.ToString()); }
  }

  private void Receive(object sender, CoreWebView2WebMessageReceivedEventArgs args) {
    var message = json.Deserialize<Dictionary<string, object>>(args.WebMessageAsJson);
    if (message.ContainsKey("__windows_webview_all_type")) {
      if (String.IsNullOrEmpty(args.Source)) { Fail("Native message source is missing"); }
      positions.Add(Convert.ToDouble(message["y"]));
    } else if (message.ContainsKey("check")) {
      double expected = Convert.ToDouble(message["y"]);
      if (positions.Count == 0 || positions[positions.Count - 1] != expected) {
        Fail(message["check"] + ": expected final position " + expected + ", received " + String.Join(",", positions) + "; state " + args.WebMessageAsJson);
      }
      if (message["exactCount"] != null && positions.Count != Convert.ToInt32(message["exactCount"])) {
        Fail(message["check"] + ": unexpected event count " + positions.Count);
      }
      positions.Clear();
      checks++;
    } else if (message.ContainsKey("failure")) {
      Fail(Convert.ToString(message["failure"]));
    } else if (message.ContainsKey("complete")) {
      if (checks != 8) { Fail("Not all test stages completed"); }
      Console.WriteLine("PASS: native WebView2 scroll bridge survives repeated document.open, immediate scroll, reset, root replacement, and reinjection (8 checks). Runtime " + view.CoreWebView2.Environment.BrowserVersionString);
      Environment.Exit(0);
    }
  }

  private static void Fail(string message) {
    Console.Error.WriteLine("FAIL: " + message);
    Environment.Exit(1);
  }

  [STAThread]
  private static void Main(string[] args) {
    Application.EnableVisualStyles();
    Application.Run(new ScrollRewriteTest(File.ReadAllText(args[0])));
  }
}
