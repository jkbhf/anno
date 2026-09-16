// The QR reader for browsers without a BarcodeDetector - Firefox, and Safari
// before 17 - served from this page instead of a CDN.
//
// mobile_scanner would otherwise pull zxing-wasm from cdn.jsdelivr.net when the
// camera opens, and the reader in turn fetches its .wasm from there too: a
// third party script running in the page that holds the Spotify login, and a
// scanner that stays blind the moment that CDN is slow or blocked.
//
// reader.js is `dist/iife/reader/index.js` of zxing-wasm, zxing_reader.wasm is
// `dist/reader/zxing_reader.wasm`, both at the version mobile_scanner pins in
// `web_library_versions.dart` (3.1.1 for mobile_scanner 7.4.0). Update the
// three together - README.md, "Camera".
ZXingWASM.setZXingModuleOverrides({
  locateFile: (path, prefix) =>
    path.endsWith('.wasm')
      ? new URL('zxing/' + path, document.baseURI).href
      : prefix + path,
});
