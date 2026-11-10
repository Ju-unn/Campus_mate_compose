import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  // 스크린샷 · 화면 녹화 방지는 릴리스 빌드에서만(디버그는 개발 · 홍보 캡처용).
  #if !DEBUG
  private weak var capturedScreen: UIScreen?
  private var coverView: UIView?

  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    guard let windowScene = scene as? UIWindowScene,
      let window = self.window ?? windowScene.windows.first
    else { return }
    // 이 시점엔 window.layer.superlayer 가 아직 없을 수 있어 한 박자 늦춘다. 그때도 못 찾으면 아무것도 안 바꾼다.
    DispatchQueue.main.async { [weak self] in self?.makeCaptureBlack(window) }
    capturedScreen = windowScene.screen
    NotificationCenter.default.addObserver(
      self, selector: #selector(updateCaptureCover),
      name: UIScreen.capturedDidChangeNotification, object: nil)
    updateCaptureCover()
  }

  // 보안 입력칸(isSecureTextEntry)의 보안 캔버스 레이어 안에 창 레이어를 넣으면 스크린샷 · 녹화에는 검게 나온다.
  // iOS 버전마다 레이어 구조가 달라 못 찾으면 아무것도 바꾸지 않고 물러난다.
  private func makeCaptureBlack(_ window: UIWindow) {
    guard let hostLayer = window.layer.superlayer else { return }
    let field = UITextField()
    field.isSecureTextEntry = true
    field.isUserInteractionEnabled = false
    field.isAccessibilityElement = false
    field.translatesAutoresizingMaskIntoConstraints = false
    window.addSubview(field)
    field.centerXAnchor.constraint(equalTo: window.centerXAnchor).isActive = true
    field.centerYAnchor.constraint(equalTo: window.centerYAnchor).isActive = true
    guard let canvas = secureCanvasLayer(of: field) else {
      field.removeFromSuperview()
      return
    }
    hostLayer.addSublayer(field.layer)
    canvas.addSublayer(window.layer)
  }

  // 보안 캔버스: 이름에 "CanvasView" 가 든 하위 뷰의 레이어. 못 찾으면 iOS 17 부터는 마지막, 그 전은 첫 번째 하위 레이어.
  private func secureCanvasLayer(of field: UITextField) -> CALayer? {
    if let canvasView = field.subviews.first(where: { String(describing: type(of: $0)).contains("CanvasView") }) {
      return canvasView.layer
    }
    if #available(iOS 17.0, *) { return field.layer.sublayers?.last }
    return field.layer.sublayers?.first
  }

  // 녹화 · 미러링 중에는 맨 위에 검은 덮개를 올리고, 끝나면 내린다.
  @objc private func updateCaptureCover() {
    guard Thread.isMainThread else {
      DispatchQueue.main.async { [weak self] in self?.updateCaptureCover() }
      return
    }
    guard let window = self.window else { return }
    if capturedScreen?.isCaptured == true {
      if coverView == nil {
        let cover = UIView(frame: window.bounds)
        cover.backgroundColor = .black
        cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        coverView = cover
      }
      if let cover = coverView {
        window.addSubview(cover)
        window.bringSubviewToFront(cover)
      }
    } else {
      coverView?.removeFromSuperview()
      coverView = nil
    }
  }
  #endif
}
