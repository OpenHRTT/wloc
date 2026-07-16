import CoreLocation
import MapKit
import SnapKit
import UIKit

final class WLocMapViewController: UIViewController {
    private lazy var vpnManager = AppWLocVPNManager(
        providerBundleIdentifier: AppWLocConfig.tunnelProviderBundleIdentifier
    )

    private let mapView = MKMapView()
    private let locationManager = CLLocationManager()
    private let geocoder = CLGeocoder()

    private let searchGlass = WLocGlassView(cornerRadius: 22, fallbackStyle: .extraLight)
    private let searchField = UITextField()
    private let searchButton = WLocGlassButton(title: "搜索", style: .secondary)

    private let resultsGlass = WLocGlassView(cornerRadius: 24, fallbackStyle: .extraLight)
    private let resultsTitleLabel = UILabel()
    private let closeResultsButton = WLocGlassButton(title: "关闭", style: .secondary)
    private let resultsTable = UITableView(frame: .zero, style: .plain)

    private let bottomGlass = WLocGlassView(cornerRadius: 28, fallbackStyle: .extraLight)
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    private let coordinateLabel = UILabel()
    private let lockButton = WLocGlassButton(title: "锁定位置", style: .primary)
    private let favoriteButton = WLocGlassButton(title: "收藏", style: .secondary)
    private let favoritesButton = WLocGlassButton(title: "收藏夹", style: .secondary)
    private let tutorialButton = WLocGlassButton(title: "教程", style: .secondary)
    private let locateButton = WLocGlassButton(title: "", style: .icon)

    private var searchResults: [AppWLocPlace] = []
    private var selectedPlace: AppWLocPlace?
    private var selectedAnnotation: MKPointAnnotation?
    private var reverseGeocodeWorkItem: DispatchWorkItem?
    private var didRequestInitialLocation = false
    private var didShowInitialUserLocation = false
    private var pendingManualLocationRequest = false
    private var shouldCenterOnUserLocation = false
    private var lastUserCoordinate: CLLocationCoordinate2D?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
        configureMap()
        configureSearch()
        configureResults()
        configureBottomPanel()
        configureLocation()
        layoutViews()
        updateEmptySelection()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !didRequestInitialLocation else { return }
        didRequestInitialLocation = true
        requestCurrentLocation(userInitiated: false)
    }

    private func configureMap() {
        mapView.delegate = self
        mapView.showsCompass = true
        mapView.showsScale = true
        mapView.showsUserLocation = true
        if #available(iOS 13.0, *) {
            mapView.pointOfInterestFilter = .includingAll
        }

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleMapTap(_:)))
        tap.cancelsTouchesInView = false
        mapView.addGestureRecognizer(tap)
    }

    private func configureSearch() {
        searchField.placeholder = "搜索地名或地址"
        searchField.returnKeyType = .search
        searchField.clearButtonMode = .whileEditing
        searchField.delegate = self
        searchField.font = .systemFont(ofSize: 16, weight: .medium)
        searchField.textColor = UIColor(red: 0.07, green: 0.1, blue: 0.16, alpha: 1)
        searchField.autocorrectionType = .no
        searchField.enablesReturnKeyAutomatically = true

        searchButton.addTarget(self, action: #selector(performSearch), for: .touchUpInside)
    }

    private func configureResults() {
        resultsGlass.isHidden = true

        resultsTitleLabel.text = "搜索结果"
        resultsTitleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        resultsTitleLabel.textColor = UIColor(red: 0.07, green: 0.1, blue: 0.16, alpha: 1)

        closeResultsButton.addTarget(self, action: #selector(closeSearchResults), for: .touchUpInside)

        resultsTable.dataSource = self
        resultsTable.delegate = self
        resultsTable.register(UITableViewCell.self, forCellReuseIdentifier: "result")
        resultsTable.backgroundColor = .clear
        resultsTable.separatorInset = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        resultsTable.keyboardDismissMode = .onDrag
        resultsTable.tableFooterView = UIView()
    }

    private func configureBottomPanel() {
        titleLabel.font = .systemFont(ofSize: 19, weight: .bold)
        titleLabel.textColor = UIColor(red: 0.05, green: 0.08, blue: 0.13, alpha: 1)
        titleLabel.numberOfLines = 1

        detailLabel.font = .systemFont(ofSize: 14, weight: .regular)
        detailLabel.textColor = UIColor(red: 0.22, green: 0.27, blue: 0.34, alpha: 1)
        detailLabel.numberOfLines = 2

        coordinateLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        coordinateLabel.textColor = UIColor(red: 0.37, green: 0.42, blue: 0.5, alpha: 1)
        coordinateLabel.numberOfLines = 1

        lockButton.addTarget(self, action: #selector(lockCurrentPlace), for: .touchUpInside)
        favoriteButton.addTarget(self, action: #selector(addFavorite), for: .touchUpInside)
        favoritesButton.addTarget(self, action: #selector(openFavorites), for: .touchUpInside)
        tutorialButton.addTarget(self, action: #selector(openTutorial), for: .touchUpInside)
        locateButton.setTitle(nil, for: .normal)
        locateButton.setImage(WLocLocationIcon.image(size: CGSize(width: 23, height: 23)), for: .normal)
        locateButton.tintColor = UIColor(red: 0.05, green: 0.16, blue: 0.28, alpha: 1)
        locateButton.imageView?.contentMode = .scaleAspectFit
        locateButton.contentEdgeInsets = UIEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        locateButton.addTarget(self, action: #selector(locateCurrentPosition), for: .touchUpInside)
    }

    private func configureLocation() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
    }

    private func layoutViews() {
        view.addSubview(mapView)
        view.addSubview(searchGlass)
        view.addSubview(resultsGlass)
        view.addSubview(locateButton)
        view.addSubview(bottomGlass)

        mapView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        searchGlass.contentView.addSubview(searchField)
        searchGlass.contentView.addSubview(searchButton)
        searchGlass.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide).offset(12)
            make.leading.trailing.equalToSuperview().inset(14)
            make.height.equalTo(56)
        }
        searchButton.snp.makeConstraints { make in
            make.trailing.equalToSuperview().inset(8)
            make.centerY.equalToSuperview()
            make.width.equalTo(68)
            make.height.equalTo(40)
        }
        searchField.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(18)
            make.trailing.equalTo(searchButton.snp.leading).offset(-10)
            make.centerY.equalToSuperview()
            make.height.equalTo(42)
        }

        resultsGlass.contentView.addSubview(resultsTitleLabel)
        resultsGlass.contentView.addSubview(closeResultsButton)
        resultsGlass.contentView.addSubview(resultsTable)
        resultsGlass.snp.makeConstraints { make in
            make.top.equalTo(searchGlass.snp.bottom).offset(10)
            make.leading.trailing.equalTo(searchGlass)
            make.height.equalTo(268)
        }
        resultsTitleLabel.snp.makeConstraints { make in
            make.top.leading.equalToSuperview().offset(16)
        }
        closeResultsButton.snp.makeConstraints { make in
            make.centerY.equalTo(resultsTitleLabel)
            make.trailing.equalToSuperview().inset(14)
            make.width.equalTo(60)
            make.height.equalTo(34)
        }
        resultsTable.snp.makeConstraints { make in
            make.top.equalTo(resultsTitleLabel.snp.bottom).offset(10)
            make.leading.trailing.bottom.equalToSuperview()
        }

        locateButton.snp.makeConstraints { make in
            make.trailing.equalToSuperview().inset(18)
            make.bottom.equalTo(bottomGlass.snp.top).offset(-14)
            make.width.height.equalTo(52)
        }

        bottomGlass.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(14)
            make.bottom.equalTo(view.safeAreaLayoutGuide).inset(14)
        }

        let secondaryRow = UIStackView(arrangedSubviews: [favoriteButton, favoritesButton, tutorialButton])
        secondaryRow.axis = .horizontal
        secondaryRow.spacing = 10
        secondaryRow.distribution = .fillEqually

        let stack = UIStackView(arrangedSubviews: [titleLabel, detailLabel, coordinateLabel, lockButton, secondaryRow])
        stack.axis = .vertical
        stack.spacing = 10
        bottomGlass.contentView.addSubview(stack)
        stack.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(18)
        }
        lockButton.snp.makeConstraints { make in
            make.height.equalTo(50)
        }
        secondaryRow.snp.makeConstraints { make in
            make.height.equalTo(44)
        }
    }

    private func updateEmptySelection() {
        selectedPlace = nil
        titleLabel.text = "选择一个位置"
        detailLabel.text = "单击地图或搜索地点选择要锁定的位置"
        coordinateLabel.text = "未选择坐标"
        lockButton.isEnabled = false
        lockButton.alpha = 0.55
        favoriteButton.isEnabled = false
        favoriteButton.alpha = 0.55
        favoriteButton.setTitle("收藏", for: .normal)
    }

    private func updateSelectedPlace(_ place: AppWLocPlace) {
        selectedPlace = place
        titleLabel.text = place.name
        detailLabel.text = place.detail.isEmpty ? "正在获取地址..." : place.detail
        coordinateLabel.text = place.coordinateText
        lockButton.isEnabled = true
        lockButton.alpha = 1
        favoriteButton.isEnabled = !AppWLocFavoriteStore.shared.contains(place)
        favoriteButton.alpha = favoriteButton.isEnabled ? 1 : 0.58
        favoriteButton.setTitle(favoriteButton.isEnabled ? "收藏" : "已收藏", for: .normal)
    }

    private func selectPlace(
        _ place: AppWLocPlace,
        shouldReverseGeocode: Bool,
        moveMap: Bool,
        animated: Bool,
        avoidingResults: Bool
    ) {
        view.endEditing(true)
        mapView.setUserTrackingMode(.none, animated: false)
        updateSelectedPlace(place)
        renderPin(for: place)
        if moveMap {
            showSelectedPlaceOnMap(place, animated: animated, avoidingResults: avoidingResults)
        }
        if shouldReverseGeocode {
            reverseGeocode(place.coordinate, fallbackName: place.name)
        }
    }

    private func renderPin(for place: AppWLocPlace) {
        if let selectedAnnotation = selectedAnnotation {
            mapView.removeAnnotation(selectedAnnotation)
        }
        let annotation = MKPointAnnotation()
        annotation.title = place.name
        annotation.subtitle = place.detail
        annotation.coordinate = place.coordinate
        selectedAnnotation = annotation
        mapView.addAnnotation(annotation)
    }

    private func showSelectedPlaceOnMap(_ place: AppWLocPlace, animated: Bool, avoidingResults: Bool) {
        let topPadding = avoidingResults && !resultsGlass.isHidden ? resultsGlass.frame.maxY + 40 : 110
        let bottomPadding = bottomGlass.frame.height + view.safeAreaInsets.bottom + 92
        moveMapToCoordinate(
            place.coordinate,
            edgePadding: UIEdgeInsets(top: topPadding, left: 42, bottom: bottomPadding, right: 42),
            animated: animated
        )
    }

    private func centerMapOnUserLocation(animated: Bool) {
        guard let coordinate = currentUserCoordinate() else { return }
        showUserLocation(coordinate, animated: animated)
    }

    private func currentUserCoordinate() -> CLLocationCoordinate2D? {
        if let coordinate = mapView.userLocation.location?.coordinate {
            return coordinate
        }
        return lastUserCoordinate
    }

    private func showUserLocation(_ coordinate: CLLocationCoordinate2D, animated: Bool) {
        if didShowInitialUserLocation {
            mapView.setCenter(coordinate, animated: animated)
        } else {
            didShowInitialUserLocation = true
            mapView.setRegion(
                MKCoordinateRegion(
                    center: coordinate,
                    latitudinalMeters: 1200,
                    longitudinalMeters: 1200
                ),
                animated: animated
            )
        }
    }

    private func moveMapToCoordinate(
        _ coordinate: CLLocationCoordinate2D,
        edgePadding: UIEdgeInsets,
        animated: Bool
    ) {
        view.layoutIfNeeded()
        let bounds = mapView.bounds
        let visibleRect = bounds.inset(by: edgePadding)
        guard bounds.width > 0, bounds.height > 0, visibleRect.width > 0, visibleRect.height > 0 else {
            mapView.setCenter(coordinate, animated: animated)
            return
        }

        let coordinatePoint = mapView.convert(coordinate, toPointTo: mapView)
        let mapCenterPoint = mapView.convert(mapView.centerCoordinate, toPointTo: mapView)
        let targetPoint = CGPoint(x: visibleRect.midX, y: visibleRect.midY)
        let nextCenterPoint = CGPoint(
            x: mapCenterPoint.x + coordinatePoint.x - targetPoint.x,
            y: mapCenterPoint.y + coordinatePoint.y - targetPoint.y
        )
        let nextCenter = mapView.convert(nextCenterPoint, toCoordinateFrom: mapView)
        mapView.setCenter(nextCenter, animated: animated)
    }

    private func reverseGeocode(_ coordinate: CLLocationCoordinate2D, fallbackName: String) {
        reverseGeocodeWorkItem?.cancel()
        geocoder.cancelGeocode()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.geocoder.reverseGeocodeLocation(CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)) { placemarks, _ in
                guard let placemark = placemarks?.first else { return }
                let detail = [placemark.name, placemark.locality, placemark.administrativeArea, placemark.country]
                    .compactMap { $0 }
                    .joined(separator: " ")
                let name = placemark.name ?? fallbackName
                let place = AppWLocPlace(name: name, detail: detail, latitude: coordinate.latitude, longitude: coordinate.longitude)
                self.updateSelectedPlace(place)
                self.selectedAnnotation?.title = place.name
                self.selectedAnnotation?.subtitle = place.detail
            }
        }
        reverseGeocodeWorkItem = workItem
        AppWLocUtils.mainThreadAfter(0.25) {
            workItem.perform()
        }
    }

    @objc private func handleMapTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        view.endEditing(true)
        let point = recognizer.location(in: mapView)
        let coordinate = mapView.convert(point, toCoordinateFrom: mapView)
        let place = AppWLocPlace(name: "自定义位置", detail: "", latitude: coordinate.latitude, longitude: coordinate.longitude)
        selectPlace(place, shouldReverseGeocode: true, moveMap: false, animated: true, avoidingResults: false)
    }

    @objc private func performSearch() {
        let query = (searchField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        view.endEditing(true)
        resultsTitleLabel.text = "搜索中..."
        resultsGlass.isHidden = false
        searchResults.removeAll()
        resultsTable.reloadData()

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = mapView.region
        MKLocalSearch(request: request).start { [weak self] response, error in
            guard let self = self else { return }
            if let error = error {
                self.resultsTitleLabel.text = "搜索结果"
                self.showMessage("搜索失败", error.localizedDescription)
                return
            }
            self.searchResults = response?.mapItems.prefix(12).map { AppWLocPlace(mapItem: $0) } ?? []
            self.resultsTitleLabel.text = self.searchResults.isEmpty ? "没有找到结果" : "搜索结果"
            self.resultsTable.reloadData()
        }
    }

    @objc private func closeSearchResults() {
        view.endEditing(true)
        resultsGlass.isHidden = true
    }

    @objc private func locateCurrentPosition() {
        view.endEditing(true)
        centerMapOnUserLocation(animated: true)
        requestCurrentLocation(userInitiated: true)
    }

    private func requestCurrentLocation(userInitiated: Bool) {
        pendingManualLocationRequest = userInitiated
        shouldCenterOnUserLocation = true
        mapView.showsUserLocation = true
        let status = CLLocationManager.authorizationStatus()
        handleLocationAuthorizationStatus(status, manager: locationManager)
    }

    private func handleLocationAuthorizationStatus(_ status: CLAuthorizationStatus, manager: CLLocationManager) {
        switch status {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            centerMapOnUserLocation(animated: pendingManualLocationRequest)
            manager.requestLocation()
        case .denied, .restricted:
            if pendingManualLocationRequest {
//                showMessage("无法定位", "请在系统设置中允许 \(AppWLocConfig.displayName) 使用当前位置。")
            }
            pendingManualLocationRequest = false
            shouldCenterOnUserLocation = false
        @unknown default:
            if pendingManualLocationRequest {
//                showMessage("无法定位", "当前系统定位权限状态不可用。")
            }
            pendingManualLocationRequest = false
            shouldCenterOnUserLocation = false
        }
    }

    @objc private func lockCurrentPlace() {
        guard let place = selectedPlace else {
            showMessage("请选择位置", "请先单击地图或搜索地点。")
            return
        }
        lock(place, successMessage: "锁定成功，请确保已【下载并信任证书】，并手动打开 设置 -> 隐私与安全性 -> 关开定位服务。")
    }

    private func lock(_ place: AppWLocPlace, successMessage: String) {
        setBusy(true, title: "锁定中...")
        vpnManager.lock(to: place) { [weak self] result in
            AppWLocUtils.mainThread {
                guard let self = self else { return }
                self.setBusy(false, title: "锁定位置")
                switch result {
                case .success:
                    self.showMessage("已锁定", successMessage)
                case .failure(let error):
                    self.showMessage("启动失败", error.localizedDescription)
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
            showMessage("链接无效", error.localizedDescription)
            return false
        }
    }

    func disconnectVPNForAppTermination() {
        vpnManager.stop(clearState: true)
    }

    private func applyExternalLocation(_ place: AppWLocPlace) {
        closeSearchResults()
        reverseGeocodeWorkItem?.cancel()
        geocoder.cancelGeocode()
        selectPlace(place, shouldReverseGeocode: place.detail.isEmpty, moveMap: true, animated: true, avoidingResults: false)
        lock(place, successMessage: "已通过外部链接保存目标位置并连接 VPN。")
    }

    @objc private func addFavorite() {
        guard let place = selectedPlace else {
            showMessage("请选择位置", "请先选择一个位置后再收藏。")
            return
        }

        let address = place.detail.isEmpty ? "暂无反查地址" : place.detail
        let alert = UIAlertController(
            title: "加入收藏",
            message: "地址：\(address)\n坐标：\(place.coordinateText)",
            preferredStyle: .alert
        )
        alert.addTextField { textField in
            textField.placeholder = "位置别名"
            textField.text = place.name == "自定义位置" ? "" : place.name
            textField.returnKeyType = .done
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "保存", style: .default) { [weak self, weak alert] _ in
            guard let self = self else { return }
            let alias = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let favorite = AppWLocPlace(
                name: alias.isEmpty ? (place.name.isEmpty ? "自定义位置" : place.name) : alias,
                detail: address,
                latitude: place.latitude,
                longitude: place.longitude
            )
            AppWLocFavoriteStore.shared.add(favorite)
            self.updateSelectedPlace(favorite)
            self.selectedAnnotation?.title = favorite.name
            self.selectedAnnotation?.subtitle = favorite.detail
        })
        present(alert, animated: true)
    }

    @objc private func openFavorites() {
        view.endEditing(true)
        let controller = WLocFavoritesViewController()
        controller.onSelect = { [weak self, weak controller] place in
            controller?.dismiss(animated: true)
            self?.selectPlace(place, shouldReverseGeocode: false, moveMap: true, animated: true, avoidingResults: false)
        }
        let navigation = UINavigationController(rootViewController: controller)
        navigation.modalPresentationStyle = .formSheet
        present(navigation, animated: true)
    }

    @objc private func openTutorial() {
        view.endEditing(true)
        let controller = WLocTutorialViewController()
        let navigation = UINavigationController(rootViewController: controller)
        navigation.modalPresentationStyle = .formSheet
        present(navigation, animated: true)
    }

    private func setBusy(_ busy: Bool, title: String) {
        lockButton.isEnabled = !busy
        lockButton.alpha = busy ? 0.7 : 1
        lockButton.setTitle(title, for: .normal)
    }

    private func showMessage(_ title: String, _ message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .default))
        present(alert, animated: true)
    }
}

extension WLocMapViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        performSearch()
        return true
    }
}

extension WLocMapViewController: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        handleLocationAuthorizationStatus(status, manager: manager)
    }

    @available(iOS 14.0, *)
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        handleLocationAuthorizationStatus(manager.authorizationStatus, manager: manager)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        lastUserCoordinate = location.coordinate
        if shouldCenterOnUserLocation {
            showUserLocation(location.coordinate, animated: true)
        }
        pendingManualLocationRequest = false
        shouldCenterOnUserLocation = false
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if let coordinate = currentUserCoordinate() {
            pendingManualLocationRequest = false
            shouldCenterOnUserLocation = false
            showUserLocation(coordinate, animated: true)
            return
        }
        let shouldShowError = pendingManualLocationRequest
        pendingManualLocationRequest = false
        shouldCenterOnUserLocation = false
        if shouldShowError {
            showMessage("定位失败", error.localizedDescription)
        }
    }
}

extension WLocMapViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        searchResults.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "result", for: indexPath)
        let place = searchResults[indexPath.row]
        cell.backgroundColor = .clear
        cell.textLabel?.numberOfLines = 2
        cell.textLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        cell.textLabel?.textColor = UIColor(red: 0.07, green: 0.1, blue: 0.16, alpha: 1)
        cell.textLabel?.text = place.detail.isEmpty ? place.name : "\(place.name)\n\(place.detail)"
        cell.selectionStyle = .default
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        view.endEditing(true)
        let place = searchResults[indexPath.row]
        searchField.text = place.name
        selectPlace(place, shouldReverseGeocode: place.detail.isEmpty, moveMap: true, animated: true, avoidingResults: true)
    }
}

extension WLocMapViewController: MKMapViewDelegate {
    func mapView(_ mapView: MKMapView, didUpdate userLocation: MKUserLocation) {
        guard let coordinate = userLocation.location?.coordinate else { return }
        lastUserCoordinate = coordinate
        if shouldCenterOnUserLocation {
            showUserLocation(coordinate, animated: true)
            pendingManualLocationRequest = false
            shouldCenterOnUserLocation = false
        }
    }

    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        guard !(annotation is MKUserLocation) else { return nil }
        let identifier = "wloc-pin"
        let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? WLocPinAnnotationView
            ?? WLocPinAnnotationView(annotation: annotation, reuseIdentifier: identifier)
        view.annotation = annotation
        return view
    }
}

private final class WLocPinAnnotationView: MKAnnotationView {
    private let pinLayer = CAShapeLayer()
    private let highlightLayer = CAShapeLayer()
    private let dotLayer = CAShapeLayer()
    private let shadowLayer = CAShapeLayer()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: 44, height: 58)
        centerOffset = CGPoint(x: 0, y: -28)
        canShowCallout = false

        isOpaque = false
        layer.addSublayer(shadowLayer)
        layer.addSublayer(pinLayer)
        layer.addSublayer(highlightLayer)
        layer.addSublayer(dotLayer)
        drawPin()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        drawPin()
    }

    private func drawPin() {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: 22, y: 56))
        path.addCurve(to: CGPoint(x: 5, y: 23), controlPoint1: CGPoint(x: 16, y: 46), controlPoint2: CGPoint(x: 5, y: 37))
        path.addCurve(to: CGPoint(x: 22, y: 4), controlPoint1: CGPoint(x: 5, y: 12), controlPoint2: CGPoint(x: 12.5, y: 4))
        path.addCurve(to: CGPoint(x: 39, y: 23), controlPoint1: CGPoint(x: 31.5, y: 4), controlPoint2: CGPoint(x: 39, y: 12))
        path.addCurve(to: CGPoint(x: 22, y: 56), controlPoint1: CGPoint(x: 39, y: 37), controlPoint2: CGPoint(x: 28, y: 46))
        path.close()

        shadowLayer.path = path.cgPath
        shadowLayer.fillColor = UIColor.black.withAlphaComponent(0.22).cgColor
        shadowLayer.shadowColor = UIColor.black.cgColor
        shadowLayer.shadowOpacity = 0.22
        shadowLayer.shadowRadius = 10
        shadowLayer.shadowOffset = CGSize(width: 0, height: 6)

        pinLayer.path = path.cgPath
        pinLayer.fillColor = UIColor(red: 1, green: 0.16, blue: 0.13, alpha: 1).cgColor

        let highlight = UIBezierPath()
        highlight.move(to: CGPoint(x: 13, y: 18))
        highlight.addCurve(to: CGPoint(x: 22, y: 9), controlPoint1: CGPoint(x: 14.5, y: 12.5), controlPoint2: CGPoint(x: 18, y: 9))
        highlight.addCurve(to: CGPoint(x: 31, y: 18), controlPoint1: CGPoint(x: 26, y: 9), controlPoint2: CGPoint(x: 29.5, y: 12.5))
        highlightLayer.path = highlight.cgPath
        highlightLayer.strokeColor = UIColor.white.withAlphaComponent(0.45).cgColor
        highlightLayer.fillColor = UIColor.clear.cgColor
        highlightLayer.lineWidth = 2
        highlightLayer.lineCap = .round

        let dot = UIBezierPath(ovalIn: CGRect(x: 15, y: 16, width: 14, height: 14))
        dotLayer.path = dot.cgPath
        dotLayer.fillColor = UIColor.white.cgColor
    }
}

private enum WLocLocationIcon {
    static func image(size: CGSize) -> UIImage {
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        defer { UIGraphicsEndImageContext() }

        let w = size.width
        let h = size.height
        let accent = UIColor(red: 0.04, green: 0.18, blue: 0.32, alpha: 1)

        let path = UIBezierPath()
        path.move(to: CGPoint(x: w * 0.52, y: h * 0.08))
        path.addLine(to: CGPoint(x: w * 0.9, y: h * 0.88))
        path.addCurve(
            to: CGPoint(x: w * 0.52, y: h * 0.67),
            controlPoint1: CGPoint(x: w * 0.82, y: h * 0.86),
            controlPoint2: CGPoint(x: w * 0.64, y: h * 0.75)
        )
        path.addCurve(
            to: CGPoint(x: w * 0.25, y: h * 0.95),
            controlPoint1: CGPoint(x: w * 0.43, y: h * 0.76),
            controlPoint2: CGPoint(x: w * 0.31, y: h * 0.88)
        )
        path.addLine(to: CGPoint(x: w * 0.52, y: h * 0.08))
        path.close()

        accent.setFill()
        path.fill()

        UIColor.white.withAlphaComponent(0.88).setStroke()
        path.lineWidth = 1.25
        path.lineJoinStyle = .round
        path.stroke()

        let shine = UIBezierPath()
        shine.move(to: CGPoint(x: w * 0.5, y: h * 0.22))
        shine.addLine(to: CGPoint(x: w * 0.68, y: h * 0.61))
        shine.lineWidth = 1.4
        shine.lineCapStyle = .round
        UIColor.white.withAlphaComponent(0.34).setStroke()
        shine.stroke()

        return UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
    }
}
