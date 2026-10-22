// A fresh value is published after each setting change so ArkUI can update
// attributes even though the settings controller itself is not observed.
export class WebViewSettingsSnapshot {
  revision: number = 0;
  backgroundColor: string = '';
  domStorageEnabled: boolean = false;
  javaScriptCanOpenWindowsAutomatically: boolean = false;
  supportMultipleWindows: boolean = false;
  javaScriptEnabled: boolean = false;
  mediaPlaybackRequiresUserGesture: boolean = false;
  supportZoom: boolean = true;
  loadWithOverviewMode: boolean = false;
  useWideViewPort: boolean = false;
  allowFileAccess: boolean = true;
  mixedContentMode: MixedMode = MixedMode.None;
  textZoom: number = 100;
}
