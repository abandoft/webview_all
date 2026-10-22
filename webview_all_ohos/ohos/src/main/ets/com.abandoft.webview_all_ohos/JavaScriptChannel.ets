import { JavaScriptChannelFlutterApiImpl } from './JavaScriptChannelFlutterApiImpl';
import web_webview from '@ohos.web.webview';

export class JavaScriptChannel {
  private readonly flutterApi: JavaScriptChannelFlutterApiImpl;
  private readonly name: string;

  constructor(flutterApi: JavaScriptChannelFlutterApiImpl, name: string) {
    if (name == null || name.length == 0) {
      throw new Error('JavaScript channel name must not be empty.');
    }
    this.flutterApi = flutterApi;
    this.name = name;
  }

  getJavaScriptChannelName(): string {
    return this.name;
  }

  createJavaScriptProxy(controller: web_webview.WebviewController): JavaScriptChannelProxy {
    return new JavaScriptChannelProxy(this, controller);
  }

  postMessage(message: string, sourceUrl: string | null): void {
    this.flutterApi.postMessage(this, message, sourceUrl, { reply: () => {} });
  }
}

export class JavaScriptChannelProxy {
  private readonly channel: JavaScriptChannel;
  private readonly controller: web_webview.WebviewController;

  constructor(channel: JavaScriptChannel, controller: web_webview.WebviewController) {
    this.channel = channel;
    this.controller = controller;
  }

  postMessage(message: ESObject): void {
    // Capture the calling frame before converting the message: conversion
    // can invoke page code and re-enter a proxy from another frame.
    let sourceUrl: string | null = null;
    try {
      sourceUrl = this.controller.getLastJavascriptProxyCallingFrameUrl();
    } catch (_) {
      // A missing sender stays unknown; never use the view's current URL.
    }
    if (sourceUrl === '') {
      sourceUrl = null;
    }
    this.channel.postMessage(String(message), sourceUrl);
  }
}
