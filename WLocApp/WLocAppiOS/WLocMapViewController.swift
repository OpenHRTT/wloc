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
    private let searchButton = WLocGlassButton(title: "", style: .icon)

    private let resultsGlass = WLocGlassView(cornerRadius: 24, fallbackStyle: .extraLight)
    private let resultsTitleLabel = UILabel()
    private let closeResultsButton = WLocGlassButton(title: "", style: .icon)
    private let resultsTable = UITableView(frame: .zero, style: .plain)

    private let bottomGlass = WLocGlassView(cornerRadius: 28, fallbackStyle: .extraLight)
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    private let coordinateLabel = UILabel()
    private let lockButton = WLocGlassButton(title: "锁定位置", style: .primary)
    private let advancedLockButton = WLocGlassButton(title: "", style: .icon)
    private let restoreButton = WLocGlassButton(title: "", style: .icon)
    private let favoriteButton = WLocGlassButton(title: "", style: .icon)
    private let moreButton = WLocGlassButton(title: "", style: .icon)
    private let tutorialButton = WLocGlassButton(title: "教程与证书", style: .secondary)
    private let dnsButton = WLocGlassButton(title: "先安装 DNS", style: .required)
    private let updateBadge = UIView()
    private let telegramButton = WLocGlassButton(title: "Telegram", style: .secondary)
    private let websiteButton = WLocGlassButton(title: "GitHub", style: .secondary)
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
    private var availableUpdate: AppWLocAvailableUpdate?
    private var isCheckingUpdates = false
    private var isLocking = false

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
        checkForUpdates(userInitiated: false)
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

        configureIconButton(searchButton, symbol: "magnifyingglass", fallback: "⌕", label: "搜索地点")
        searchButton.addTarget(self, action: #selector(performSearch), for: .touchUpInside)
    }

    private func configureResults() {
        resultsGlass.isHidden = true

        resultsTitleLabel.text = "搜索结果"
        resultsTitleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        resultsTitleLabel.textColor = UIColor(red: 0.07, green: 0.1, blue: 0.16, alpha: 1)

        configureIconButton(closeResultsButton, symbol: "xmark", fallback: "×", label: "关闭搜索结果")
        closeResultsButton.addTarget(self, action: #selector(closeSearchResults), for: .touchUpInside)

        resultsTable.dataSource = self
        resultsTable.delegate = self
        resultsTable.register(UITableViewCell.self, forCellReuseIdentifier: "result")
        resultsTable.backgroundColor = .clear
        resultsTable.separatorInset = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        resultsTable.keyboardDismissMode = .onDrag
        resultsTable.tableFooterView = UIView()
    }

    /// DNS 安装入口用醒目的橙色，定位和教程入口沿用蓝色。
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

        configureIconButton(advancedLockButton, symbol: "slider.horizontal.3", fallback: "☷", label: "高级锁定")
        advancedLockButton.accessibilityHint = "设置海拔、水平精度和垂直精度后锁定"
        configureIconButton(restoreButton, symbol: "arrow.counterclockwise", fallback: "↶", label: "还原定位")
        configureIconButton(favoriteButton, symbol: "star", fallback: "☆", label: "收藏当前位置")
        favoriteButton.backgroundColor = .clear
        favoriteButton.layer.borderWidth = 0
        favoriteButton.adjustsImageWhenDisabled = false
        configureIconButton(moreButton, symbol: "ellipsis", fallback: "•••", label: "更多功能")
        moreButton.accessibilityHint = "收藏夹、经纬度、日志和检查更新"
        moreButton.addTarget(self, action: #selector(openMoreMenu), for: .touchUpInside)
        updateBadge.backgroundColor = UIColor(red: 0.06, green: 0.35, blue: 0.95, alpha: 1)
        updateBadge.layer.cornerRadius = 3
        updateBadge.isHidden = true
        updateBadge.isUserInteractionEnabled = false
        moreButton.addSubview(updateBadge)
        updateBadge.snp.makeConstraints { make in
            make.top.trailing.equalToSuperview().inset(9)
            make.width.height.equalTo(6)
        }

        lockButton.addTarget(self, action: #selector(lockCurrentPlace), for: .touchUpInside)
        advancedLockButton.addTarget(self, action: #selector(openAdvancedLock), for: .touchUpInside)
        restoreButton.addTarget(self, action: #selector(restoreLocation), for: .touchUpInside)
        favoriteButton.addTarget(self, action: #selector(addFavorite), for: .touchUpInside)
        configureExternalLinkButton(
            tutorialButton,
            image: WLocExternalIcon.image(named: "book.closed.fill", fallback: .symbol("▤"), size: CGSize(width: 16, height: 16)),
            color: UIColor(red: 0.06, green: 0.35, blue: 0.95, alpha: 1),
            accessibilityLabel: "教程与证书"
        )
        tutorialButton.backgroundColor = UIColor(red: 0.06, green: 0.35, blue: 0.95, alpha: 1)
        tutorialButton.tintColor = .white
        tutorialButton.setTitleColor(.white, for: .normal)
        tutorialButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        tutorialButton.layer.cornerRadius = 14
        tutorialButton.layer.borderColor = UIColor.white.withAlphaComponent(0.35).cgColor
        tutorialButton.layer.shadowOpacity = 0.18
        tutorialButton.layer.shadowRadius = 10
        tutorialButton.layer.shadowOffset = CGSize(width: 0, height: 4)
        tutorialButton.accessibilityHint = "查看使用教程、下载并安装定位证书"
        tutorialButton.addTarget(self, action: #selector(openTutorial), for: .touchUpInside)
        configureExternalLinkButton(
            dnsButton,
            image: WLocExternalIcon.image(named: "exclamationmark.shield.fill", fallback: .symbol("!"), size: CGSize(width: 18, height: 18)),
            color: .white,
            accessibilityLabel: "使用前请先安装 DNS，查看安装说明"
        )
        dnsButton.backgroundColor = UIColor(red: 0.85, green: 0.29, blue: 0.04, alpha: 1)
        dnsButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .bold)
        dnsButton.addTarget(self, action: #selector(openTutorial), for: .touchUpInside)
        configureExternalLinkButton(
            telegramButton,
            image: WLocExternalIcon.image(named: "paperplane.fill", fallback: .telegram, size: CGSize(width: 16, height: 16)),
            color: UIColor(red: 0.08, green: 0.43, blue: 0.68, alpha: 1),
            accessibilityLabel: "打开 Telegram"
        )
        telegramButton.addTarget(self, action: #selector(openTelegram), for: .touchUpInside)
        configureExternalLinkButton(
            websiteButton,
            image: WLocExternalIcon.image(named: "chevron.left.forwardslash.chevron.right", fallback: .code, size: CGSize(width: 16, height: 16)),
            color: UIColor(red: 0.2, green: 0.24, blue: 0.3, alpha: 1),
            accessibilityLabel: "查看 GitHub 开源项目"
        )
        websiteButton.addTarget(self, action: #selector(openWebsite), for: .touchUpInside)
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

    /// DNS 提示和教程入口并排放在搜索框下方，始终保留安装说明入口。
    private func layoutViews() {
        view.addSubview(mapView)
        view.addSubview(searchGlass)
        view.addSubview(tutorialButton)
        view.addSubview(dnsButton)
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
            make.width.height.equalTo(44)
        }
        searchField.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(18)
            make.trailing.equalTo(searchButton.snp.leading).offset(-10)
            make.centerY.equalToSuperview()
            make.height.equalTo(42)
        }
        tutorialButton.snp.makeConstraints { make in
            make.top.equalTo(searchGlass.snp.bottom).offset(12)
            make.trailing.equalTo(searchGlass)
            make.width.equalTo(136)
            make.height.equalTo(44)
        }
        dnsButton.snp.makeConstraints { make in
            make.top.height.equalTo(tutorialButton)
            make.leading.equalTo(searchGlass)
            make.trailing.equalTo(tutorialButton.snp.leading).offset(-10)
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
            make.leading.equalToSuperview().offset(16)
            make.centerY.equalTo(closeResultsButton)
        }
        closeResultsButton.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(8)
            make.trailing.equalToSuperview().inset(14)
            make.width.height.equalTo(44)
        }
        resultsTable.snp.makeConstraints { make in
            make.top.equalTo(closeResultsButton.snp.bottom).offset(8)
            make.leading.trailing.bottom.equalToSuperview()
        }

        locateButton.snp.makeConstraints { make in
            make.trailing.equalToSuperview().inset(18)
            make.bottom.equalTo(bottomGlass.snp.top).offset(-14)
            make.width.height.equalTo(52)
        }

        bottomGlass.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(14)
            make.bottom.equalTo(view.safeAreaLayoutGuide)
        }

        let actionRow = UIStackView(arrangedSubviews: [lockButton, advancedLockButton, restoreButton])
        actionRow.axis = .horizontal
        actionRow.spacing = 8
        actionRow.alignment = .center
        [advancedLockButton, restoreButton, favoriteButton, moreButton].forEach { button in
            button.snp.makeConstraints { make in make.width.height.equalTo(44) }
        }
        lockButton.snp.makeConstraints { make in make.height.equalTo(48) }

        let externalLinkRow = UIStackView(arrangedSubviews: [telegramButton, websiteButton])
        externalLinkRow.axis = .horizontal
        externalLinkRow.spacing = 8
        externalLinkRow.distribution = .fillEqually

        let footerRow = UIStackView(arrangedSubviews: [externalLinkRow, moreButton])
        footerRow.axis = .horizontal
        footerRow.spacing = 8
        footerRow.alignment = .center

        let headingRow = UIStackView(arrangedSubviews: [titleLabel, favoriteButton])
        headingRow.axis = .horizontal
        headingRow.spacing = 8
        headingRow.alignment = .center
        titleLabel.lineBreakMode = .byTruncatingTail

        let stack = UIStackView(arrangedSubviews: [headingRow, detailLabel, coordinateLabel, actionRow, footerRow])
        stack.axis = .vertical
        stack.spacing = 10
        stack.setCustomSpacing(2, after: headingRow)
        stack.setCustomSpacing(4, after: detailLabel)
        bottomGlass.contentView.addSubview(stack)
        stack.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(16)
        }
        actionRow.snp.makeConstraints { make in
            make.height.equalTo(48)
        }
        externalLinkRow.snp.makeConstraints { make in
            make.height.equalTo(44)
        }
    }

    /// 图标按钮保留无障碍名称，触摸区域由布局统一保证为 44 点。
    private func configureIconButton(_ button: WLocGlassButton, symbol: String, fallback: String, label: String) {
        button.setImage(WLocExternalIcon.image(named: symbol, fallback: .symbol(fallback), size: CGSize(width: 21, height: 21)).withRenderingMode(.alwaysTemplate), for: .normal)
        button.tintColor = UIColor(red: 0.24, green: 0.3, blue: 0.37, alpha: 1)
        button.contentEdgeInsets = UIEdgeInsets(top: 11, left: 11, bottom: 11, right: 11)
        button.imageView?.contentMode = .scaleAspectFit
        button.layer.cornerRadius = 12
        button.layer.shadowOpacity = 0
        button.backgroundColor = UIColor.white.withAlphaComponent(0.3)
        button.accessibilityLabel = label
    }

    /// 社区入口保留图标和名称，使用淡品牌色，避免抢过锁定按钮。
    private func configureExternalLinkButton(_ button: WLocGlassButton, image: UIImage, color: UIColor, accessibilityLabel: String) {
        button.setImage(image.withRenderingMode(.alwaysTemplate), for: .normal)
        button.tintColor = color
        button.setTitleColor(color, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        button.contentEdgeInsets = UIEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
        button.backgroundColor = color.withAlphaComponent(0.09)
        button.layer.borderColor = color.withAlphaComponent(0.13).cgColor
        button.layer.cornerRadius = 12
        button.layer.shadowOpacity = 0
        button.imageView?.contentMode = .scaleAspectFit
        button.semanticContentAttribute = .forceLeftToRight
        button.imageEdgeInsets = UIEdgeInsets(top: 0, left: -4, bottom: 0, right: 6)
        button.titleEdgeInsets = UIEdgeInsets(top: 0, left: 4, bottom: 0, right: -4)
        button.accessibilityLabel = accessibilityLabel
    }

    /// 未选点时禁用锁定和收藏，保留还原与更多入口。
    private func updateEmptySelection() {
        selectedPlace = nil
        titleLabel.text = "选择一个位置"
        detailLabel.text = "单击地图或搜索地点选择要锁定的位置"
        coordinateLabel.text = "未选择坐标"
        lockButton.isEnabled = false
        lockButton.alpha = 0.55
        advancedLockButton.isEnabled = false
        advancedLockButton.alpha = 0.55
        updateFavoriteButton()
    }

    /// 更新地点信息时同步锁定按钮和收藏星标的状态。
    private func updateSelectedPlace(_ place: AppWLocPlace) {
        selectedPlace = place
        titleLabel.text = place.name
        detailLabel.text = place.detail.isEmpty ? "正在获取地址..." : place.detail
        coordinateLabel.text = place.coordinateText
        lockButton.isEnabled = !isLocking
        lockButton.alpha = isLocking ? 0.7 : 1
        advancedLockButton.isEnabled = !isLocking
        advancedLockButton.alpha = isLocking ? 0.7 : 1
        updateFavoriteButton()
    }

    /// 用空心和实心星标区分未收藏、已收藏，不再占用一整排按钮。
    private func updateFavoriteButton() {
        let isSaved = selectedPlace.map { AppWLocFavoriteStore.shared.contains($0) } ?? false
        favoriteButton.isEnabled = selectedPlace != nil && !isSaved
        favoriteButton.alpha = selectedPlace == nil ? 0.45 : 1
        favoriteButton.tintColor = isSaved ? UIColor(red: 0.75, green: 0.5, blue: 0.1, alpha: 1)
            : UIColor(red: 0.24, green: 0.3, blue: 0.37, alpha: 1)
        favoriteButton.setImage(WLocExternalIcon.image(named: isSaved ? "star.fill" : "star", fallback: .symbol(isSaved ? "★" : "☆"), size: CGSize(width: 21, height: 21)).withRenderingMode(.alwaysTemplate), for: .normal)
        favoriteButton.accessibilityLabel = isSaved ? "当前位置已收藏" : "收藏当前位置"
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
                let detail = AppWLocPlace.detailedAddress(from: placemark)
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

    /// 坐标来源菜单从更多入口弹出，iPad 也有有效的弹窗锚点。
    @objc private func openCoordinateInput() {
        view.endEditing(true)
        let sheet = UIAlertController(title: "选择坐标来源", message: nil, preferredStyle: .actionSheet)
        AppWLocCoordinateSystem.allCases.forEach { system in
            sheet.addAction(UIAlertAction(title: system.inputTitle, style: .default) { [weak self] _ in
                self?.showCoordinateInput(for: system)
            })
        }
        sheet.addAction(UIAlertAction(title: "取消", style: .cancel))
        sheet.popoverPresentationController?.sourceView = moreButton
        sheet.popoverPresentationController?.sourceRect = moreButton.bounds
        present(sheet, animated: true)
    }

    private func showCoordinateInput(for sourceSystem: AppWLocCoordinateSystem) {
        let alert = UIAlertController(
            title: "输入经纬度",
            message: "坐标来源：\(sourceSystem.inputTitle)",
            preferredStyle: .alert
        )
        alert.addTextField { textField in
            textField.placeholder = "纬度，例如 39.9087"
            textField.keyboardType = .numbersAndPunctuation
            textField.autocorrectionType = .no
            textField.spellCheckingType = .no
        }
        alert.addTextField { textField in
            textField.placeholder = "经度，例如 116.3975"
            textField.keyboardType = .numbersAndPunctuation
            textField.autocorrectionType = .no
            textField.spellCheckingType = .no
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "在地图上定位", style: .default) { [weak self, weak alert] _ in
            guard let self = self, let fields = alert?.textFields, fields.count == 2 else { return }
            self.applyCoordinateInput(
                latitudeText: fields[0].text ?? "",
                longitudeText: fields[1].text ?? "",
                sourceSystem: sourceSystem
            )
        })
        present(alert, animated: true)
    }

    private func applyCoordinateInput(
        latitudeText: String,
        longitudeText: String,
        sourceSystem: AppWLocCoordinateSystem
    ) {
        do {
            let coordinate = try AppWLocCoordinateTool.appleMapCoordinate(
                latitudeText: latitudeText,
                longitudeText: longitudeText,
                sourceSystem: sourceSystem
            )
            closeSearchResults()
            let place = AppWLocPlace(
                name: "经纬度位置",
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            )
            selectPlace(place, shouldReverseGeocode: true, moveMap: true, animated: false, avoidingResults: false)
        } catch {
            let message = error.localizedDescription
            AppWLocUtils.mainThreadAfter(0.2) { [weak self] in
                self?.showMessage("坐标无效", message)
            }
        }
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
        lock(place)
    }

    @objc private func openAdvancedLock() {
        guard let place = selectedPlace, !isLocking else { return }
        view.endEditing(true)
        let controller = WLocAdvancedLockViewController(place: place) { [weak self] parameters in
            self?.lock(place, parameters: parameters)
        }
        let navigation = UINavigationController(rootViewController: controller)
        navigation.modalPresentationStyle = .formSheet
        present(navigation, animated: true)
    }

    @objc private func restoreLocation() {
        view.endEditing(true)
        showMessage("还原定位", "请先关闭 VPN，然后前往“设置 → 隐私与安全性 → 定位服务”，关闭定位服务，等待 2 秒后重新开启，以刷新实际位置。")
    }

    /// 普通锁定和高级锁定共用 VPN 流程，只传入不同的定位参数。
    private func lock(
        _ place: AppWLocPlace,
        parameters: AppWLocLockParameters = AppWLocLockParameters(),
        successMessage: String = "锁定成功，请确保已下载并信任证书，然后前往“设置 → 隐私与安全性 → 定位服务”，关闭定位服务，等待 2 秒后重新开启。"
    ) {
        guard !isLocking else { return }
        setBusy(true, title: "锁定中...")
        vpnManager.lock(to: place, parameters: parameters) { [weak self] result in
            AppWLocUtils.mainThread {
                guard let self = self else { return }
                self.setBusy(false, title: "锁定位置")
                switch result {
                case .success:
                    self.showMessage("已锁定", successMessage)
                case .failure(let error):
                    self.showVPNStartError(error)
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

    /// 选中坐标即可收藏，无需等待详细地址解析完成。
    @objc private func addFavorite() {
        guard let place = selectedPlace else {
            showMessage("请选择位置", "请先选择一个位置后再收藏。")
            return
        }

        let favorite = AppWLocFavorite(place: place, alias: "")
        let alert = UIAlertController(
            title: "加入收藏",
            message: "地点：\(favorite.title)\n地址：\(favorite.detail)\n坐标：\(favorite.coordinateText)",
            preferredStyle: .alert
        )
        alert.addTextField { textField in
            textField.placeholder = "自定义别名（可选）"
            textField.text = ""
            textField.returnKeyType = .done
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "保存", style: .default) { [weak self, weak alert] _ in
            guard let self = self else { return }
            let alias = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let favorite = AppWLocFavorite(place: place, alias: alias)
            AppWLocFavoriteStore.shared.add(favorite)
            self.updateSelectedPlace(place)
        })
        present(alert, animated: true)
    }

    /// 低频工具集中到更多菜单；先关闭菜单，再显示下一页，避免叠加弹窗。
    @objc private func openMoreMenu() {
        view.endEditing(true)
        guard presentedViewController == nil else { return }
        let sheet = UIAlertController(title: "更多功能", message: "\(AppWLocConfig.displayName) · 版本 \(AppWLocConfig.currentVersion)", preferredStyle: .actionSheet)
        let updateTitle = isCheckingUpdates ? "正在检查更新…" : availableUpdate.map { "下载更新 v\($0.version)" } ?? "检查更新"
        let items: [(String, (WLocMapViewController) -> Void)] = [
            ("收藏夹", { $0.openFavorites() }),
            ("输入经纬度", { $0.openCoordinateInput() }),
            ("查看日志", { $0.openDebugLog() }),
            (updateTitle, { $0.openUpdate() })
        ]
        for (title, action) in items {
            let item = UIAlertAction(title: title, style: .default) { [weak self, weak sheet] _ in
                guard let self else { return }
                if let sheet, sheet.presentingViewController != nil {
                    sheet.dismiss(animated: true) { action(self) }
                } else {
                    action(self)
                }
            }
            item.isEnabled = title != updateTitle || !isCheckingUpdates
            sheet.addAction(item)
        }
        sheet.addAction(UIAlertAction(title: "取消", style: .cancel))
        sheet.popoverPresentationController?.sourceView = moreButton
        sheet.popoverPresentationController?.sourceRect = moreButton.bounds
        present(sheet, animated: true)
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

    @objc private func openTelegram() {
        openExternalURL(WLocExternalLink.telegram)
    }

    @objc private func openWebsite() {
        openExternalURL(WLocExternalLink.github)
    }

    @objc private func openDebugLog() {
        view.endEditing(true)
        let controller = WLocDebugLogViewController()
        let navigation = UINavigationController(rootViewController: controller)
        navigation.modalPresentationStyle = .formSheet
        present(navigation, animated: true)
    }

    /// 更多菜单里的更新入口沿用原来的安装包跳转逻辑。
    private func openUpdate() {
        if let availableUpdate {
            openExternalURL(availableUpdate.downloadURL)
        } else {
            checkForUpdates(userInitiated: true)
        }
    }

    /// 自动检查只显示小圆点；主动检查发现新版时弹出下载提示。
    private func checkForUpdates(userInitiated: Bool) {
        guard !isCheckingUpdates else { return }
        isCheckingUpdates = true
        moreButton.accessibilityValue = "正在检查更新"
        AppWLocUpdateChecker.shared.check(platform: .iOS) { [weak self] result in
            guard let self = self else { return }
            self.isCheckingUpdates = false
            switch result {
            case .updateAvailable(let update):
                self.availableUpdate = update
                if userInitiated, self.presentedViewController == nil {
                    let alert = UIAlertController(title: "发现新版本 v\(update.version)", message: "当前版本：\(AppWLocConfig.currentVersion)", preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "稍后", style: .cancel))
                    alert.addAction(UIAlertAction(title: "查看安装包", style: .default) { [weak self] _ in self?.openExternalURL(update.downloadURL) })
                    self.present(alert, animated: true)
                }
            case .upToDate(let latestVersion):
                self.availableUpdate = nil
                if userInitiated {
                    self.showMessage("已是最新版本", "当前版本：\(AppWLocConfig.currentVersion)\n最新版本：\(latestVersion)")
                }
            case .failure(let error):
                if userInitiated {
                    self.showMessage("检查更新失败", error.localizedDescription)
                } else {
                    AppWLocUtils.debugLog("\(AppWLocConfig.displayName) iOS 自动检查更新失败：\(error.localizedDescription)")
                }
            }
            self.updateBadge.isHidden = self.availableUpdate == nil
            self.moreButton.accessibilityValue = self.availableUpdate.map { "有新版本 v\($0.version)" }
        }
    }

    private func openExternalURL(_ url: URL) {
        view.endEditing(true)
        UIApplication.shared.open(url, options: [:])
    }

    private func setBusy(_ busy: Bool, title: String) {
        isLocking = busy
        lockButton.isEnabled = !busy && selectedPlace != nil
        lockButton.alpha = busy ? 0.7 : 1
        lockButton.setTitle(title, for: .normal)
        advancedLockButton.isEnabled = lockButton.isEnabled
        advancedLockButton.alpha = lockButton.alpha
        restoreButton.isEnabled = !busy
    }

    private func showMessage(_ title: String, _ message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .default))
        present(alert, animated: true)
    }

    /// VPN 权限错误换成中文指引，其他启动错误继续显示原来的原因。
    private func showVPNStartError(_ error: Error) {
        var currentError: NSError? = error as NSError
        while let cause = currentError {
            if cause.localizedDescription.range(of: "permission denied", options: .caseInsensitive) != nil {
                showMessage("VPN 配置失败或当前证书无 VPN 权限", "请允许添加 VPN 配置后重试；若仍然失败，请使用具备 VPN 权限的证书重新签名并安装应用。")
                return
            }
            currentError = cause.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        showMessage("启动失败", error.localizedDescription)
    }
}

private final class WLocAdvancedLockViewController: UIViewController {
    private let place: AppWLocPlace
    private let onLock: (AppWLocLockParameters) -> Void
    private let altitudeField = UITextField()
    private let horizontalField = UITextField()
    private let verticalField = UITextField()
    private let queryButton = WLocGlassButton(title: "查询海拔", style: .secondary)
    private let lockButton = WLocGlassButton(title: "锁定位置", style: .primary)
    private let statusLabel = UILabel()
    private var elevationTask: URLSessionDataTask?

    init(place: AppWLocPlace, onLock: @escaping (AppWLocLockParameters) -> Void) {
        self.place = place
        self.onLock = onLock
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    deinit { elevationTask?.cancel() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "高级锁定"
        view.backgroundColor = UIColor(white: 0.97, alpha: 1)
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "取消", style: .plain, target: self, action: #selector(close))

        // 坐标固定为打开表单时选中的位置，查询海拔和最终锁定使用同一个点。
        let parameters = AppWLocLockParameters(state: AppWLocStateStore.shared.load())
        altitudeField.text = NSNumber(value: parameters.altitude).stringValue
        horizontalField.text = String(parameters.horizontalAccuracy)
        verticalField.text = String(parameters.verticalAccuracy)
        altitudeField.keyboardType = .numbersAndPunctuation
        horizontalField.keyboardType = .numberPad
        verticalField.keyboardType = .numberPad

        let toolbar = UIToolbar()
        toolbar.items = [
            UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
            UIBarButtonItem(title: "完成", style: .done, target: self, action: #selector(endEditing))
        ]
        toolbar.sizeToFit()
        [altitudeField, horizontalField, verticalField].forEach { $0.inputAccessoryView = toolbar }
        queryButton.addTarget(self, action: #selector(queryElevation), for: .touchUpInside)
        lockButton.addTarget(self, action: #selector(confirmLock), for: .touchUpInside)
        statusLabel.font = .systemFont(ofSize: 13)
        statusLabel.textColor = .darkGray
        statusLabel.numberOfLines = 0

        let coordinates = UIStackView(arrangedSubviews: [
            coordinateView(title: "纬度", value: String(format: "%.7f", place.latitude)),
            coordinateView(title: "经度", value: String(format: "%.7f", place.longitude))
        ])
        coordinates.axis = .horizontal
        coordinates.spacing = 12
        coordinates.distribution = .fillEqually

        let scrollView = UIScrollView()
        scrollView.keyboardDismissMode = .interactive
        view.addSubview(scrollView)
        view.addSubview(lockButton)
        let stack = UIStackView(arrangedSubviews: [
            label("当前选择", heading: true), coordinates, label("定位参数", heading: true),
            parameterView(title: "海拔高度（m）", field: altitudeField), queryButton,
            parameterView(title: "水平精度（m，非负整数）", field: horizontalField),
            parameterView(title: "垂直精度（m，非负整数）", field: verticalField), statusLabel
        ])
        stack.axis = .vertical
        stack.spacing = 16
        scrollView.addSubview(stack)
        lockButton.snp.makeConstraints { make in
            make.leading.trailing.equalTo(view.safeAreaLayoutGuide).inset(20)
            make.bottom.equalTo(view.safeAreaLayoutGuide).inset(16)
            make.height.equalTo(50)
        }
        scrollView.snp.makeConstraints { make in
            make.top.leading.trailing.equalTo(view.safeAreaLayoutGuide)
            make.bottom.equalTo(lockButton.snp.top).offset(-16)
        }
        stack.snp.makeConstraints { make in
            make.edges.equalTo(scrollView.contentLayoutGuide).inset(20)
            make.width.equalTo(scrollView.frameLayoutGuide).offset(-40)
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        elevationTask?.cancel()
        elevationTask = nil
    }

    private func label(_ text: String, heading: Bool = false) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: heading ? 19 : 14, weight: .semibold)
        label.textColor = heading ? .black : .darkGray
        label.numberOfLines = 0
        return label
    }

    private func coordinateView(title: String, value: String) -> UIView {
        let stack = UIStackView(arrangedSubviews: [label(title), label(value)])
        stack.axis = .vertical
        stack.spacing = 8
        return stack
    }

    private func parameterView(title: String, field: UITextField) -> UIView {
        field.font = .systemFont(ofSize: 20)
        field.textColor = .black
        field.backgroundColor = .white
        field.borderStyle = .roundedRect
        field.clearButtonMode = .whileEditing
        field.autocorrectionType = .no
        field.accessibilityLabel = title
        field.snp.makeConstraints { make in make.height.equalTo(48) }
        let stack = UIStackView(arrangedSubviews: [label(title), field])
        stack.axis = .vertical
        stack.spacing = 8
        return stack
    }

    @objc private func endEditing() { view.endEditing(true) }

    @objc private func close() { dismiss(animated: true) }

    @objc private func queryElevation() {
        view.endEditing(true)
        queryButton.isEnabled = false
        queryButton.setTitle("查询中…", for: .normal)
        statusLabel.text = nil
        let coordinate = AppWLocCoordinateTool.wlocResponseCoordinate(fromAppleMapCoordinate: place.coordinate)
        elevationTask = AppWLocElevationQuery.query(latitude: coordinate.latitude, longitude: coordinate.longitude) { [weak self] result in
            guard let self, self.elevationTask != nil else { return }
            self.elevationTask = nil
            self.queryButton.isEnabled = true
            self.queryButton.setTitle("查询海拔", for: .normal)
            switch result {
            case .success(let elevation):
                self.altitudeField.text = NSNumber(value: elevation).stringValue
                self.statusLabel.textColor = .darkGray
                self.statusLabel.text = "已填入查询海拔，可继续手动修改。"
            case .failure(let error):
                self.statusLabel.textColor = .red
                self.statusLabel.text = error.localizedDescription
            }
        }
    }

    @objc private func confirmLock() {
        do {
            let parameters = try AppWLocLockParameters(
                altitudeText: altitudeField.text ?? "",
                horizontalAccuracyText: horizontalField.text ?? "",
                verticalAccuracyText: verticalField.text ?? ""
            )
            elevationTask?.cancel()
            elevationTask = nil
            view.endEditing(true)
            dismiss(animated: true) { [onLock] in onLock(parameters) }
        } catch {
            statusLabel.textColor = .red
            statusLabel.text = error.localizedDescription
        }
    }
}

private final class WLocDebugLogViewController: UIViewController {
    private let textView = UITextView()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "调试日志"
        if #available(iOS 13.0, *) {
            view.backgroundColor = .systemBackground
            textView.backgroundColor = .systemBackground
            textView.textColor = .label
        } else {
            view.backgroundColor = .white
            textView.backgroundColor = .white
            textView.textColor = .black
        }
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(close)
        )
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(title: "清空", style: .plain, target: self, action: #selector(clearLog)),
            UIBarButtonItem(barButtonSystemItem: .refresh, target: self, action: #selector(reloadLog))
        ]

        textView.isEditable = false
        textView.isSelectable = true
        textView.alwaysBounceVertical = true
        textView.font = UIFont(name: "Menlo-Regular", size: 11) ?? .systemFont(ofSize: 11)
        textView.textContainerInset = UIEdgeInsets(top: 14, left: 10, bottom: 14, right: 10)
        view.addSubview(textView)
        textView.snp.makeConstraints { make in
            make.edges.equalTo(view.safeAreaLayoutGuide)
        }

        reloadLog()
    }

    @objc private func close() {
        dismiss(animated: true)
    }

    @objc private func reloadLog() {
        AppWLocUtils.readDebugLog { [weak self] content in
            self?.textView.text = content
        }
    }

    @objc private func clearLog() {
        AppWLocUtils.clearDebugLog { [weak self] in
            self?.reloadLog()
        }
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
        selectPlace(place, shouldReverseGeocode: place.detail.isEmpty, moveMap: true, animated: false, avoidingResults: true)
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

private enum WLocExternalLink {
    static let telegram = URL(string: "https://t.me/wloc88")!
    static let website = URL(string: "https://wloc8.com/")!
    static let github = URL(string: "https://github.com/OpenHRTT/wloc")!
}

enum WLocExternalIcon {
    enum Fallback {
        case telegram
        case code
        case symbol(String)
    }

    /// 优先使用系统图标，iOS 12 使用字形绘制的图标保持入口可见。
    static func image(named systemName: String, fallback: Fallback, size: CGSize) -> UIImage {
        if #available(iOS 13.0, *), let systemImage = UIImage(systemName: systemName, withConfiguration: UIImage.SymbolConfiguration(pointSize: size.height, weight: .medium)) {
            return systemImage
        }

        return fallbackImage(fallback, size: size)
    }

    /// 老系统也提供星标、还原和更多等图标，不退回成文字按钮。
    private static func fallbackImage(_ icon: Fallback, size: CGSize) -> UIImage {
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        defer { UIGraphicsEndImageContext() }

        let color = UIColor(red: 0.08, green: 0.12, blue: 0.18, alpha: 1)
        color.setStroke()
        color.setFill()

        switch icon {
        case .telegram:
            drawTelegramIcon(in: CGRect(origin: .zero, size: size))
        case .code:
            drawCodeIcon(in: CGRect(origin: .zero, size: size))
        case .symbol(let symbol):
            let text = NSAttributedString(string: symbol, attributes: [.font: UIFont.systemFont(ofSize: size.height * 0.9, weight: .medium), .foregroundColor: color])
            let textSize = text.size()
            text.draw(at: CGPoint(x: (size.width - textSize.width) / 2, y: (size.height - textSize.height) / 2))
        }

        return UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
    }

    private static func drawTelegramIcon(in rect: CGRect) {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.08, y: rect.minY + rect.height * 0.45))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.92, y: rect.minY + rect.height * 0.12))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.72, y: rect.minY + rect.height * 0.9))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.45, y: rect.minY + rect.height * 0.64))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.3, y: rect.minY + rect.height * 0.78))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.35, y: rect.minY + rect.height * 0.58))
        path.close()
        path.fill()
    }

    private static func drawCodeIcon(in rect: CGRect) {
        let left = UIBezierPath()
        left.move(to: CGPoint(x: rect.minX + rect.width * 0.38, y: rect.minY + rect.height * 0.22))
        left.addLine(to: CGPoint(x: rect.minX + rect.width * 0.16, y: rect.minY + rect.height * 0.5))
        left.addLine(to: CGPoint(x: rect.minX + rect.width * 0.38, y: rect.minY + rect.height * 0.78))
        left.lineWidth = 2
        left.lineCapStyle = .round
        left.lineJoinStyle = .round
        left.stroke()

        let right = UIBezierPath()
        right.move(to: CGPoint(x: rect.minX + rect.width * 0.62, y: rect.minY + rect.height * 0.22))
        right.addLine(to: CGPoint(x: rect.minX + rect.width * 0.84, y: rect.minY + rect.height * 0.5))
        right.addLine(to: CGPoint(x: rect.minX + rect.width * 0.62, y: rect.minY + rect.height * 0.78))
        right.lineWidth = 2
        right.lineCapStyle = .round
        right.lineJoinStyle = .round
        right.stroke()

        let slash = UIBezierPath()
        slash.move(to: CGPoint(x: rect.minX + rect.width * 0.56, y: rect.minY + rect.height * 0.18))
        slash.addLine(to: CGPoint(x: rect.minX + rect.width * 0.44, y: rect.minY + rect.height * 0.82))
        slash.lineWidth = 2
        slash.lineCapStyle = .round
        slash.stroke()
    }
}
