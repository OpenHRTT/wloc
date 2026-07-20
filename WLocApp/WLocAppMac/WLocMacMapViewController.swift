import AppKit
import CoreLocation
import MapKit
import SnapKit

private final class WLocArrowCursorMapView: MKMapView {
    private var arrowTrackingArea: NSTrackingArea?

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .arrow)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let arrowTrackingArea {
            removeTrackingArea(arrowTrackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        arrowTrackingArea = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        NSCursor.arrow.set()
        super.mouseEntered(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
        NSCursor.arrow.set()
        super.mouseMoved(with: event)
    }
}

final class WLocMacMapViewController: NSViewController {
    private lazy var vpnManager = AppWLocVPNManager(
        providerBundleIdentifier: AppWLocConfig.tunnelProviderBundleIdentifier
    )

    private let mapView = WLocArrowCursorMapView()
    private let searchField = NSSearchField()
    private let searchTable = NSTableView()
    private let favoritesTable = NSTableView()
    private let zoomInButton = NSButton.wlocButton("+")
    private let zoomOutButton = NSButton.wlocButton("−")
    private let currentLocationButton = NSButton.wlocButton("⌖")
    private let titleLabel = NSTextField.wlocLabel("地图中心")
    private let detailLabel = NSTextField.wlocLabel("")
    private let coordinateLabel = NSTextField.wlocLabel("")
    private let lockButton = NSButton.wlocButton("锁定位置")
    private let favoriteButton = NSButton.wlocButton("加入收藏")
    private let tutorialButton = NSButton.wlocButton("教程与证书")
    private let telegramButton = NSButton.wlocButton("Telegram")
    private let websiteButton = NSButton.wlocButton("WLoc8.com")
    private let selectedAnnotation = MKPointAnnotation()

    private let geocoder = CLGeocoder()
    private let locationManager = CLLocationManager()
    private var searchResults: [AppWLocPlace] = []
    private var favorites: [AppWLocPlace] = []
    private var selectedPlace: AppWLocPlace?
    private var hasSelectedAnnotation = false
    private var reverseGeocodeWorkItem: DispatchWorkItem?
    private var tutorialWindow: WLocMacTutorialWindowController?
    private var mapClickGesture: NSClickGestureRecognizer?
    private weak var controlsPanel: NSView?
    private var shouldSelectNextLocationUpdate = false
    private var isRefreshingLocationAfterLock = false

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureViews()
        layoutViews()
        reloadFavorites()
        let initialPlace = AppWLocPlace(name: "上海", detail: "单击地图可选择新的位置", latitude: 31.2304, longitude: 121.4737)
        updateSelectedPlace(initialPlace)
        updateSelectedAnnotation(with: initialPlace)
    }

    private func configureViews() {
        mapView.delegate = self
        mapView.showsCompass = true
        mapView.showsScale = true
        mapView.showsUserLocation = false
        let clickGesture = NSClickGestureRecognizer(target: self, action: #selector(selectMapPoint(_:)))
        clickGesture.numberOfClicksRequired = 1
        clickGesture.delegate = self
        if #available(macOS 10.12, *) {
            clickGesture.delaysPrimaryMouseButtonEvents = false
        }
        mapClickGesture = clickGesture
        mapView.addGestureRecognizer(clickGesture)
        mapView.setRegion(
            MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 31.2304, longitude: 121.4737),
                latitudinalMeters: 12000,
                longitudinalMeters: 12000
            ),
            animated: false
        )

        selectedAnnotation.coordinate = CLLocationCoordinate2D(latitude: 31.2304, longitude: 121.4737)
        selectedAnnotation.title = "地图中心"

        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest

        searchField.placeholderString = "搜索地名或地址"
        searchField.delegate = self
        searchField.target = self
        searchField.action = #selector(performSearch)
        searchField.font = .systemFont(ofSize: 15)

        configureTable(searchTable)
        configureTable(favoritesTable)

        titleLabel.font = .systemFont(ofSize: 22, weight: .semibold)
        detailLabel.font = .systemFont(ofSize: 13)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.maximumNumberOfLines = 2
        detailLabel.cell?.wraps = true
        coordinateLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        coordinateLabel.textColor = .secondaryLabelColor

        [lockButton, favoriteButton, tutorialButton, telegramButton, websiteButton].forEach {
            $0.bezelStyle = .rounded
            $0.controlSize = .regular
        }
        configureExternalLinkButton(
            telegramButton,
            image: WLocMacExternalIcon.image(named: "paperplane.fill", fallback: .telegram, size: NSSize(width: 17, height: 17)),
            toolTip: "打开 Telegram: https://t.me/wloc88"
        )
        configureExternalLinkButton(
            websiteButton,
            image: WLocMacExternalIcon.image(named: "chevron.left.forwardslash.chevron.right", fallback: .code, size: NSSize(width: 17, height: 17)),
            toolTip: "打开 WLoc8.com 官网: https://wloc8.com/"
        )
        [zoomInButton, zoomOutButton, currentLocationButton].forEach(configureMapControlButton)

        lockButton.target = self
        lockButton.action = #selector(lockCurrentPlace)
        favoriteButton.target = self
        favoriteButton.action = #selector(addFavorite)
        tutorialButton.target = self
        tutorialButton.action = #selector(openTutorial)
        telegramButton.target = self
        telegramButton.action = #selector(openTelegram)
        websiteButton.target = self
        websiteButton.action = #selector(openWebsite)
        zoomInButton.target = self
        zoomInButton.action = #selector(zoomIn)
        zoomOutButton.target = self
        zoomOutButton.action = #selector(zoomOut)
        currentLocationButton.target = self
        currentLocationButton.action = #selector(centerOnCurrentLocation)
    }

    private func configureTable(_ table: NSTableView) {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("main"))
        column.title = ""
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.headerView = nil
        table.rowHeight = 54
        table.delegate = self
        table.dataSource = self
        table.selectionHighlightStyle = .regular
        table.backgroundColor = .clear
    }

    private func configureMapControlButton(_ button: NSButton) {
        if #available(macOS 26.0, *) {
            button.bezelStyle = .glass
        } else {
            button.bezelStyle = .texturedRounded
        }
        button.font = .systemFont(ofSize: 18, weight: .semibold)
    }

    private func configureExternalLinkButton(_ button: NSButton, image: NSImage, toolTip: String) {
        button.image = image
        button.imagePosition = .imageLeft
        button.toolTip = toolTip
    }

    private func layoutViews() {
        let sidebar = LiquidGlassEffectView(
            effect: LiquidGlassEffect(style: .regular, isNative: true),
            cornerRadius: 28
        )
        let controlsPanel = LiquidGlassEffectView(
            effect: LiquidGlassEffect(style: .regular, isNative: true),
            cornerRadius: 23
        )
        self.controlsPanel = controlsPanel

        view.addSubview(mapView)
        view.addSubview(sidebar)
        view.addSubview(controlsPanel)

        controlsPanel.contentView.addSubview(zoomInButton)
        controlsPanel.contentView.addSubview(zoomOutButton)
        controlsPanel.contentView.addSubview(currentLocationButton)

        mapView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        sidebar.snp.makeConstraints { make in
            make.leading.equalToSuperview().inset(24)
            make.top.equalToSuperview().inset(64)
            make.bottom.equalToSuperview().inset(24)
            make.width.equalTo(408)
        }
        controlsPanel.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(72)
            make.trailing.equalToSuperview().inset(28)
            make.width.equalTo(54)
            make.height.equalTo(164)
        }
        
        zoomInButton.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(8)
            make.centerX.equalToSuperview()
            make.width.height.equalTo(42)
        }
        zoomOutButton.snp.makeConstraints { make in
            make.top.equalTo(zoomInButton.snp.bottom).offset(10)
            make.centerX.equalToSuperview()
            make.width.height.equalTo(zoomInButton)
        }
        currentLocationButton.snp.makeConstraints { make in
            make.top.equalTo(zoomOutButton.snp.bottom).offset(10)
            make.centerX.equalToSuperview()
            make.width.height.equalTo(zoomInButton)
        }

        let searchScroll = NSScrollView()
        searchScroll.documentView = searchTable
        searchScroll.hasVerticalScroller = true
        searchScroll.borderType = .noBorder

        let resultTitle = NSTextField.wlocLabel("搜索结果")
        resultTitle.font = .systemFont(ofSize: 13, weight: .semibold)
        resultTitle.textColor = .secondaryLabelColor

        let favoriteTitle = NSTextField.wlocLabel("收藏地点")
        favoriteTitle.font = .systemFont(ofSize: 13, weight: .semibold)
        favoriteTitle.textColor = .secondaryLabelColor

        let favoritesScroll = NSScrollView()
        favoritesScroll.documentView = favoritesTable
        favoritesScroll.hasVerticalScroller = true
        favoritesScroll.borderType = .noBorder

        let actionStack = NSStackView(views: [lockButton, favoriteButton])
        actionStack.orientation = .horizontal
        actionStack.spacing = 10
        actionStack.distribution = .fillEqually

        let secondaryActionStack = NSStackView(views: [tutorialButton])
        secondaryActionStack.orientation = .vertical
        secondaryActionStack.spacing = 8
        secondaryActionStack.distribution = .fillEqually

        let externalLinkStack = NSStackView(views: [telegramButton, websiteButton])
        externalLinkStack.orientation = .horizontal
        externalLinkStack.spacing = 10
        externalLinkStack.distribution = .fillEqually
        secondaryActionStack.addArrangedSubview(externalLinkStack)

        [lockButton, favoriteButton, tutorialButton, telegramButton, websiteButton].forEach { button in
            button.snp.makeConstraints { make in
                make.height.equalTo(36)
            }
        }

        [searchField, titleLabel, detailLabel, coordinateLabel, resultTitle, searchScroll, actionStack, secondaryActionStack, favoriteTitle, favoritesScroll].forEach {
            sidebar.contentView.addSubview($0)
        }

        actionStack.orientation = .horizontal
        actionStack.distribution = .fillEqually

        searchField.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(20)
            make.leading.trailing.equalToSuperview().inset(18)
            make.height.equalTo(36)
        }
        titleLabel.snp.makeConstraints { make in
            make.top.equalTo(searchField.snp.bottom).offset(18)
            make.leading.trailing.equalTo(searchField)
        }
        detailLabel.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(8)
            make.leading.trailing.equalTo(searchField)
        }
        coordinateLabel.snp.makeConstraints { make in
            make.top.equalTo(detailLabel.snp.bottom).offset(8)
            make.leading.trailing.equalTo(searchField)
        }
        actionStack.snp.makeConstraints { make in
            make.top.equalTo(coordinateLabel.snp.bottom).offset(16)
            make.leading.trailing.equalTo(searchField)
        }
        secondaryActionStack.snp.makeConstraints { make in
            make.top.equalTo(actionStack.snp.bottom).offset(10)
            make.leading.trailing.equalTo(searchField)
        }
        resultTitle.snp.makeConstraints { make in
            make.top.equalTo(secondaryActionStack.snp.bottom).offset(20)
            make.leading.trailing.equalTo(searchField)
        }
        searchScroll.snp.makeConstraints { make in
            make.top.equalTo(resultTitle.snp.bottom).offset(8)
            make.leading.trailing.equalTo(searchField)
            make.height.equalTo(210)
        }
        favoriteTitle.snp.makeConstraints { make in
            make.top.equalTo(searchScroll.snp.bottom).offset(20)
            make.leading.trailing.equalTo(searchField)
        }
        favoritesScroll.snp.makeConstraints { make in
            make.top.equalTo(favoriteTitle.snp.bottom).offset(8)
            make.leading.trailing.equalTo(searchField)
            make.bottom.equalToSuperview().inset(16)
        }
    }

    private func updateSelectedPlace(_ place: AppWLocPlace) {
        selectedPlace = place
        titleLabel.stringValue = place.name
        detailLabel.stringValue = place.detail
        coordinateLabel.stringValue = place.coordinateText
        favoriteButton.isEnabled = !AppWLocFavoriteStore.shared.contains(place)
        favoriteButton.title = favoriteButton.isEnabled ? "加入收藏" : "已收藏"
    }

    private func moveMap(to place: AppWLocPlace) {
        mapView.setRegion(
            MKCoordinateRegion(center: place.coordinate, latitudinalMeters: 800, longitudinalMeters: 800),
            animated: true
        )
        updateSelectedPlace(place)
        updateSelectedAnnotation(with: place)
    }

    private func updateSelectedAnnotation(with place: AppWLocPlace) {
        selectedAnnotation.coordinate = place.coordinate
        selectedAnnotation.title = place.name
        selectedAnnotation.subtitle = place.detail
        if !hasSelectedAnnotation {
            mapView.addAnnotation(selectedAnnotation)
            hasSelectedAnnotation = true
        }
    }

    private func selectCoordinate(_ coordinate: CLLocationCoordinate2D, name: String = "查询中...", detail: String = "") {
        let place = AppWLocPlace(name: name, detail: detail, latitude: coordinate.latitude, longitude: coordinate.longitude)
        updateSelectedPlace(place)
        updateSelectedAnnotation(with: place)

        reverseGeocodeWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.geocoder.cancelGeocode()
            self.geocoder.reverseGeocodeLocation(CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)) { placemarks, _ in
                guard let placemark = placemarks?.first else { return }
                let detail = [placemark.locality, placemark.administrativeArea, placemark.country]
                    .compactMap { $0 }
                    .joined(separator: " ")
                let resolvedPlace = AppWLocPlace(
                    name: placemark.name ?? name,
                    detail: detail,
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude
                )
                self.updateSelectedPlace(resolvedPlace)
                self.updateSelectedAnnotation(with: resolvedPlace)
            }
        }
        reverseGeocodeWorkItem = workItem
        AppWLocUtils.mainThreadAfter(0.45) {
            workItem.perform()
        }
    }

    private func reloadFavorites() {
        favorites = AppWLocFavoriteStore.shared.all()
        favoritesTable.reloadData()
    }

    @objc private func lockCurrentPlace() {
        guard let place = selectedPlace else { return }
        var msg = "锁定成功。请确认已安装并始终信任证书，然后关闭系统定位服务，等待两秒后再打开。"
        #if DEBUG
        let logPath = AppWLocUtils.debugLogURL?.path ?? "/tmp/AppWLoc/wloc-debug.log"
        msg += "\n\n调试日志：\(logPath)"
        #endif
        lock(place, successMessage:msg)
    }

    private func lock(_ place: AppWLocPlace, successMessage: String) {
        lockButton.isEnabled = false
        lockButton.title = "锁定中..."
        vpnManager.lock(to: place) { [weak self] result in
            AppWLocUtils.mainThread {
                guard let self else { return }
                self.lockButton.isEnabled = true
                switch result {
                case .success:
                    self.lockButton.title = "锁定位置"
                    AppWLocUtils.mainThreadAfter(2.0) { [weak self] in
                        self?.startSystemLocationRefresh(selectResult: false)
                    }
                    self.showAlert(title: "已锁定", message: successMessage)
                case .failure(let error):
                    self.lockButton.title = "锁定位置"
                    self.showAlert(title: "启动失败", message: error.localizedDescription)
                }
            }
        }
    }

    @discardableResult
    func handleDeepLink(_ url: URL) -> Bool {
        do {
            switch try WLocURLCommandParser.parse(url) {
            case .location(let place):
                applyExternalLocation(place)
            }
            return true
        } catch {
            showAlert(title: "链接无效", message: error.localizedDescription)
            return false
        }
    }

    func disconnectVPNForAppTermination() {
        vpnManager.stop(clearState: true)
    }

    private func applyExternalLocation(_ place: AppWLocPlace) {
        view.window?.makeFirstResponder(nil)
        reverseGeocodeWorkItem?.cancel()
        geocoder.cancelGeocode()
        moveMap(to: place)
        lock(place, successMessage: "已通过外部链接保存目标位置并连接 VPN。")
    }

    @objc private func addFavorite() {
        guard let place = selectedPlace else { return }
        AppWLocFavoriteStore.shared.add(place)
        updateSelectedPlace(place)
        reloadFavorites()
    }

    @objc private func openTutorial() {
        let controller = WLocMacTutorialWindowController()
        tutorialWindow = controller
        controller.showWindow(self)
    }

    @objc private func openTelegram() {
        openExternalURL(WLocMacExternalLink.telegram)
    }

    @objc private func openWebsite() {
        openExternalURL(WLocMacExternalLink.website)
    }

    private func openExternalURL(_ url: URL) {
        view.window?.makeFirstResponder(nil)
        NSWorkspace.shared.open(url)
    }

    @objc private func performSearch() {
        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = mapView.region
        MKLocalSearch(request: request).start { [weak self] response, error in
            guard let self else { return }
            if let error {
                self.showAlert(title: "搜索失败", message: error.localizedDescription)
                return
            }
            self.searchResults = response?.mapItems.prefix(12).map { AppWLocPlace(mapItem: $0) } ?? []
            self.searchTable.reloadData()
//            if let first = self.searchResults.first {
//                self.moveMap(to: first)
//            }
        }
    }

    @objc private func zoomIn() {
        view.window?.makeFirstResponder(nil)
        NSCursor.arrow.set()
        zoomMap(by: 0.5)
    }

    @objc private func zoomOut() {
        view.window?.makeFirstResponder(nil)
        NSCursor.arrow.set()
        zoomMap(by: 2.0)
    }

    @objc private func selectMapPoint(_ recognizer: NSClickGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        guard shouldSelectMapPoint(for: recognizer) else { return }
        view.window?.makeFirstResponder(nil)
        NSCursor.arrow.set()
        let point = recognizer.location(in: mapView)
        let coordinate = mapView.convert(point, toCoordinateFrom: mapView)
        selectCoordinate(coordinate)
    }

    private func shouldSelectMapPoint(for recognizer: NSGestureRecognizer) -> Bool {
        guard let superview = mapView.superview else { return true }
        let point = recognizer.location(in: superview)
        guard let hitView = mapView.hitTest(point) else { return true }

        if hitView is NSControl {
            return false
        }
        if let controlsPanel, hitView.isDescendant(of: controlsPanel) {
            return false
        }

        return true
    }

    private func zoomMap(by multiplier: CLLocationDegrees) {
        let span = MKCoordinateSpan(
            latitudeDelta: max(mapView.region.span.latitudeDelta * multiplier, 0.0005),
            longitudeDelta: max(mapView.region.span.longitudeDelta * multiplier, 0.0005)
        )
        mapView.setRegion(MKCoordinateRegion(center: mapView.centerCoordinate, span: span), animated: true)
    }

    @objc private func centerOnCurrentLocation() {
        view.window?.makeFirstResponder(nil)
        NSCursor.arrow.set()

        if let location = mapView.userLocation.location ?? locationManager.location {
            centerMap(on: location.coordinate, meters: 1200)
            return
        }

        startSystemLocationRefresh(selectResult: true)
    }

    private func startSystemLocationRefresh(selectResult: Bool) {
        shouldSelectNextLocationUpdate = selectResult
        isRefreshingLocationAfterLock = !selectResult
        mapView.showsUserLocation = true

        let status = CLLocationManager.authorizationStatus()
        AppWLocUtils.debugLog(
            "\(AppWLocConfig.displayName) macOS 准备刷新系统定位 selectResult=\(selectResult)，status=\(authorizationStatusDescription(status))"
        )
        switch status {
        case .notDetermined:
            if #available(macOS 10.15, *) {
                locationManager.requestWhenInUseAuthorization()
            }
            AppWLocUtils.debugLog("\(AppWLocConfig.displayName) macOS 请求定位权限并启动定位刷新")
            locationManager.startUpdatingLocation()
        case .authorizedAlways, .authorizedWhenInUse:
            AppWLocUtils.debugLog("\(AppWLocConfig.displayName) macOS 启动定位刷新 selectResult=\(selectResult)")
            locationManager.startUpdatingLocation()
        default:
            AppWLocUtils.debugLog(
                "\(AppWLocConfig.displayName) macOS 定位当前不可用，等待用户重新开启定位服务 status=\(authorizationStatusDescription(status))"
            )
            if selectResult {
                shouldSelectNextLocationUpdate = false
                isRefreshingLocationAfterLock = false
                showAlert(title: "无法定位", message: "请在系统设置中允许 \(AppWLocConfig.displayName) 使用定位服务。")
            }
        }
    }

    private func handleLocationAuthorizationChange(_ status: CLAuthorizationStatus) {
        let hasLockedState = AppWLocStateStore.shared.load() != nil
        AppWLocUtils.debugLog(
            "\(AppWLocConfig.displayName) macOS 定位授权变化 status=\(authorizationStatusDescription(status))，afterLock=\(isRefreshingLocationAfterLock)，selectNext=\(shouldSelectNextLocationUpdate)，locked=\(hasLockedState)"
        )
        guard isRefreshingLocationAfterLock || shouldSelectNextLocationUpdate || hasLockedState else { return }

        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            if hasLockedState && !isRefreshingLocationAfterLock && !shouldSelectNextLocationUpdate {
                AppWLocUtils.debugLog("\(AppWLocConfig.displayName) macOS 检测到已锁定坐标，定位服务恢复后补发定位刷新")
                isRefreshingLocationAfterLock = true
            }
            AppWLocUtils.debugLog("\(AppWLocConfig.displayName) macOS 定位已恢复，补发定位刷新")
            mapView.showsUserLocation = true
            locationManager.startUpdatingLocation()
        case .denied, .restricted:
            AppWLocUtils.debugLog("\(AppWLocConfig.displayName) macOS 定位仍不可用，保持等待")
        case .notDetermined:
            if #available(macOS 10.15, *) {
                locationManager.requestWhenInUseAuthorization()
            }
        @unknown default:
            AppWLocUtils.debugLog("\(AppWLocConfig.displayName) macOS 未知定位授权状态")
        }
    }

    private func authorizationStatusDescription(_ status: CLAuthorizationStatus) -> String {
        switch status {
        case .notDetermined:
            return "notDetermined"
        case .restricted:
            return "restricted"
        case .denied:
            return "denied"
        case .authorizedAlways:
            return "authorizedAlways"
        case .authorizedWhenInUse:
            return "authorizedWhenInUse"
        @unknown default:
            return "unknown(\(status.rawValue))"
        }
    }

    private func centerMap(on coordinate: CLLocationCoordinate2D, meters: CLLocationDistance) {
        mapView.setRegion(
            MKCoordinateRegion(center: coordinate, latitudinalMeters: meters, longitudinalMeters: meters),
            animated: true
        )
        selectCoordinate(coordinate, name: "当前位置", detail: "来自系统定位")
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "好")
        alert.beginSheetModal(for: view.window ?? NSWindow()) { _ in }
    }
}

extension WLocMacMapViewController: NSSearchFieldDelegate {
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard commandSelector == #selector(NSResponder.insertNewline(_:)) else {
            return false
        }
        performSearch()
        return true
    }
}

extension WLocMacMapViewController: NSGestureRecognizerDelegate {
    func gestureRecognizerShouldBegin(_ gestureRecognizer: NSGestureRecognizer) -> Bool {
        guard gestureRecognizer === mapClickGesture else {
            return true
        }
        return shouldSelectMapPoint(for: gestureRecognizer)
    }
}

extension WLocMacMapViewController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        tableView == searchTable ? searchResults.count : favorites.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("cell")
        let textField = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTextField ?? NSTextField.wlocLabel("")
        textField.identifier = identifier
        textField.lineBreakMode = .byTruncatingTail
        textField.maximumNumberOfLines = 2
        textField.font = .systemFont(ofSize: 13)
        if tableView == searchTable {
            let item = searchResults[row]
            textField.stringValue = item.detail.isEmpty ? item.name : "\(item.name)\n\(item.detail)"
        } else {
            let place = favorites[row]
            textField.stringValue = "\(place.name)\n\(place.coordinateText)"
        }
        return textField
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let tableView = notification.object as? NSTableView, tableView.selectedRow >= 0 else { return }
        if tableView == favoritesTable {
            moveMap(to: favorites[tableView.selectedRow])
            return
        }

        moveMap(to: searchResults[tableView.selectedRow])
    }
}

extension WLocMacMapViewController: MKMapViewDelegate {
    
}

extension WLocMacMapViewController: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        handleLocationAuthorizationChange(status)
    }

    @available(macOS 11.0, *)
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        handleLocationAuthorizationChange(manager.authorizationStatus)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        manager.stopUpdatingLocation()
        AppWLocUtils.debugLog(
            "\(AppWLocConfig.displayName) macOS 收到定位更新 lat=\(location.coordinate.latitude), lng=\(location.coordinate.longitude)"
        )
        let shouldSelect = shouldSelectNextLocationUpdate
        shouldSelectNextLocationUpdate = false
        isRefreshingLocationAfterLock = false
        if shouldSelect {
            centerMap(on: location.coordinate, meters: 1200)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        manager.stopUpdatingLocation()
        AppWLocUtils.debugLog("\(AppWLocConfig.displayName) macOS 定位刷新失败：\(error.localizedDescription)")
        let shouldShowError = shouldSelectNextLocationUpdate || !isRefreshingLocationAfterLock
        shouldSelectNextLocationUpdate = false
        isRefreshingLocationAfterLock = false
        if shouldShowError {
            showAlert(title: "定位失败", message: error.localizedDescription)
        }
    }
}

private enum WLocMacExternalLink {
    static let telegram = URL(string: "https://t.me/wloc88")!
    static let website = URL(string: "https://wloc8.com/")!
}

private enum WLocMacExternalIcon {
    enum Fallback {
        case telegram
        case code
    }

    static func image(named systemName: String, fallback: Fallback, size: NSSize) -> NSImage {
        if #available(macOS 11.0, *), let systemImage = NSImage(systemSymbolName: systemName, accessibilityDescription: nil) {
            systemImage.size = size
            return systemImage
        }

        return fallbackImage(fallback, size: size)
    }

    private static func fallbackImage(_ icon: Fallback, size: NSSize) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.labelColor.set()

        let rect = NSRect(origin: .zero, size: size)
        switch icon {
        case .telegram:
            drawTelegramIcon(in: rect)
        case .code:
            drawCodeIcon(in: rect)
        }

        image.unlockFocus()
        return image
    }

    private static func drawTelegramIcon(in rect: NSRect) {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: rect.minX + rect.width * 0.08, y: rect.minY + rect.height * 0.55))
        path.line(to: NSPoint(x: rect.minX + rect.width * 0.92, y: rect.minY + rect.height * 0.88))
        path.line(to: NSPoint(x: rect.minX + rect.width * 0.72, y: rect.minY + rect.height * 0.1))
        path.line(to: NSPoint(x: rect.minX + rect.width * 0.45, y: rect.minY + rect.height * 0.36))
        path.line(to: NSPoint(x: rect.minX + rect.width * 0.3, y: rect.minY + rect.height * 0.22))
        path.line(to: NSPoint(x: rect.minX + rect.width * 0.35, y: rect.minY + rect.height * 0.42))
        path.close()
        path.fill()
    }

    private static func drawCodeIcon(in rect: NSRect) {
        let left = NSBezierPath()
        left.move(to: NSPoint(x: rect.minX + rect.width * 0.38, y: rect.minY + rect.height * 0.78))
        left.line(to: NSPoint(x: rect.minX + rect.width * 0.16, y: rect.minY + rect.height * 0.5))
        left.line(to: NSPoint(x: rect.minX + rect.width * 0.38, y: rect.minY + rect.height * 0.22))
        left.lineWidth = 2
        left.lineCapStyle = .round
        left.lineJoinStyle = .round
        left.stroke()

        let right = NSBezierPath()
        right.move(to: NSPoint(x: rect.minX + rect.width * 0.62, y: rect.minY + rect.height * 0.78))
        right.line(to: NSPoint(x: rect.minX + rect.width * 0.84, y: rect.minY + rect.height * 0.5))
        right.line(to: NSPoint(x: rect.minX + rect.width * 0.62, y: rect.minY + rect.height * 0.22))
        right.lineWidth = 2
        right.lineCapStyle = .round
        right.lineJoinStyle = .round
        right.stroke()

        let slash = NSBezierPath()
        slash.move(to: NSPoint(x: rect.minX + rect.width * 0.56, y: rect.minY + rect.height * 0.82))
        slash.line(to: NSPoint(x: rect.minX + rect.width * 0.44, y: rect.minY + rect.height * 0.18))
        slash.lineWidth = 2
        slash.lineCapStyle = .round
        slash.stroke()
    }
}
