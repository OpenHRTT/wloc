import AppKit
import CoreLocation
import MapKit
import SnapKit

final class WLocMacMapViewController: NSViewController {
    private lazy var vpnManager = AppWLocVPNManager(
        providerBundleIdentifier: AppWLocConfig.tunnelProviderBundleIdentifier
    )

    private let mapView = MKMapView()
    private let searchField = NSSearchField()
    private let searchTable = NSTableView()
    private let favoritesTable = NSTableView()
    private let titleLabel = NSTextField.wlocLabel("地图中心")
    private let detailLabel = NSTextField.wlocLabel("")
    private let coordinateLabel = NSTextField.wlocLabel("")
    private let lockButton = NSButton.wlocButton("锁定位置")
    private let favoriteButton = NSButton.wlocButton("加入收藏")
    private let tutorialButton = NSButton.wlocButton("教程与证书")
    private let pinLabel = NSTextField.wlocLabel("⌖")

    private let geocoder = CLGeocoder()
    private var searchResults: [AppWLocPlace] = []
    private var favorites: [AppWLocPlace] = []
    private var selectedPlace: AppWLocPlace?
    private var reverseGeocodeWorkItem: DispatchWorkItem?
    private var tutorialWindow: WLocMacTutorialWindowController?
    private var ignoresNextRegionChange = false

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
        updateSelectedPlace(AppWLocPlace(name: "地图中心", latitude: 31.2304, longitude: 121.4737))
    }

    private func configureViews() {
        mapView.delegate = self
        mapView.showsCompass = true
        mapView.showsScale = true
        mapView.setRegion(
            MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 31.2304, longitude: 121.4737),
                latitudinalMeters: 6000,
                longitudinalMeters: 6000
            ),
            animated: false
        )

        pinLabel.alignment = .center
        pinLabel.font = .systemFont(ofSize: 34, weight: .semibold)
        pinLabel.textColor = .systemRed
        pinLabel.backgroundColor = .clear

        searchField.placeholderString = "搜索地名或地址"
        searchField.delegate = self
        searchField.target = self
        searchField.action = #selector(performSearch)

        configureTable(searchTable)
        configureTable(favoritesTable)

        titleLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        detailLabel.font = .systemFont(ofSize: 13)
        detailLabel.textColor = .secondaryLabelColor
        coordinateLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        coordinateLabel.textColor = .secondaryLabelColor

        [lockButton, favoriteButton, tutorialButton].forEach {
            $0.bezelStyle = .rounded
            $0.controlSize = .regular
        }
        lockButton.target = self
        lockButton.action = #selector(lockCurrentPlace)
        favoriteButton.target = self
        favoriteButton.action = #selector(addFavorite)
        tutorialButton.target = self
        tutorialButton.action = #selector(openTutorial)
    }

    private func configureTable(_ table: NSTableView) {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("main"))
        column.title = ""
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = 54
        table.delegate = self
        table.dataSource = self
        table.selectionHighlightStyle = .regular
    }

    private func layoutViews() {
        let sidebar = NSView()
        sidebar.wantsLayer = true
        sidebar.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        view.addSubview(sidebar)
        view.addSubview(mapView)
        mapView.addSubview(pinLabel)

        sidebar.snp.makeConstraints { make in
            make.leading.top.bottom.equalToSuperview()
            make.width.equalTo(330)
        }
        mapView.snp.makeConstraints { make in
            make.leading.equalTo(sidebar.snp.trailing)
            make.top.trailing.bottom.equalToSuperview()
        }
        pinLabel.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.width.height.equalTo(48)
        }

        let searchScroll = NSScrollView()
        searchScroll.documentView = searchTable
        searchScroll.hasVerticalScroller = true
        searchScroll.borderType = .noBorder

        let favoriteTitle = NSTextField.wlocLabel("收藏")
        favoriteTitle.font = .systemFont(ofSize: 15, weight: .semibold)

        let favoritesScroll = NSScrollView()
        favoritesScroll.documentView = favoritesTable
        favoritesScroll.hasVerticalScroller = true
        favoritesScroll.borderType = .noBorder

        let actionStack = NSStackView(views: [lockButton, favoriteButton, tutorialButton])
        actionStack.orientation = .vertical
        actionStack.spacing = 8
        actionStack.distribution = .fillEqually

        [searchField, searchScroll, titleLabel, detailLabel, coordinateLabel, actionStack, favoriteTitle, favoritesScroll].forEach {
            sidebar.addSubview($0)
        }

        searchField.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(18)
            make.leading.trailing.equalToSuperview().inset(16)
        }
        searchScroll.snp.makeConstraints { make in
            make.top.equalTo(searchField.snp.bottom).offset(10)
            make.leading.trailing.equalTo(searchField)
            make.height.equalTo(170)
        }
        titleLabel.snp.makeConstraints { make in
            make.top.equalTo(searchScroll.snp.bottom).offset(18)
            make.leading.trailing.equalTo(searchField)
        }
        detailLabel.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(6)
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
        favoriteTitle.snp.makeConstraints { make in
            make.top.equalTo(actionStack.snp.bottom).offset(20)
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
        detailLabel.stringValue = place.detail.isEmpty ? "移动地图微调位置，或搜索一个地名" : place.detail
        coordinateLabel.stringValue = place.coordinateText
        favoriteButton.isEnabled = !AppWLocFavoriteStore.shared.contains(place)
        favoriteButton.title = favoriteButton.isEnabled ? "加入收藏" : "已收藏"
    }

    private func moveMap(to place: AppWLocPlace) {
        ignoresNextRegionChange = true
        mapView.setRegion(
            MKCoordinateRegion(center: place.coordinate, latitudinalMeters: 800, longitudinalMeters: 800),
            animated: true
        )
        updateSelectedPlace(place)
        mapView.removeAnnotations(mapView.annotations)
        let annotation = MKPointAnnotation()
        annotation.coordinate = place.coordinate
        annotation.title = place.name
        annotation.subtitle = place.detail
        mapView.addAnnotation(annotation)
    }

    private func refreshPlaceForMapCenter() {
        let coordinate = mapView.centerCoordinate
        updateSelectedPlace(AppWLocPlace(name: "地图中心", latitude: coordinate.latitude, longitude: coordinate.longitude))

        reverseGeocodeWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.geocoder.cancelGeocode()
            self.geocoder.reverseGeocodeLocation(CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)) { placemarks, _ in
                guard let placemark = placemarks?.first else { return }
                let detail = [placemark.locality, placemark.administrativeArea, placemark.country]
                    .compactMap { $0 }
                    .joined(separator: " ")
                self.updateSelectedPlace(AppWLocPlace(
                    name: placemark.name ?? "地图中心",
                    detail: detail,
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude
                ))
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
        lock(place, successMessage: "锁定成功。")
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
            if let first = self.searchResults.first {
                self.moveMap(to: first)
            }
        }
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
    func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
        if ignoresNextRegionChange {
            ignoresNextRegionChange = false
            return
        }
        refreshPlaceForMapCenter()
    }
}
