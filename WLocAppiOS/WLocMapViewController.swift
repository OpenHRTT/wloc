import CoreLocation
import MapKit
import SnapKit
import UIKit

final class WLocMapViewController: UIViewController {
    private let providerBundleIdentifier = "com.wlocapp.ios.tunnel"
    private lazy var vpnManager = WLocVPNManager(providerBundleIdentifier: providerBundleIdentifier)

    private let mapView = MKMapView()
    private let searchBar = UISearchBar()
    private let suggestionsTable = UITableView(frame: .zero, style: .plain)
    private let bottomPanel = UIVisualEffectView(effect: UIBlurEffect(style: .extraLight))
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    private let coordinateLabel = UILabel()
    private let lockButton = UIButton(type: .system)
    private let favoriteButton = UIButton(type: .system)
    private let favoritesButton = UIButton(type: .system)
    private let tutorialButton = UIButton(type: .system)
    private let centerPin = UILabel()

    private let completer = MKLocalSearchCompleter()
    private let geocoder = CLGeocoder()
    private var searchResults: [MKLocalSearchCompletion] = []
    private var selectedPlace: WLocPlace?
    private var reverseGeocodeWorkItem: DispatchWorkItem?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = AppWLocConfig.displayName
        view.backgroundColor = .white
        configureMap()
        configureSearch()
        configureBottomPanel()
        layoutViews()
        updateSelectedPlace(
            WLocPlace(name: "地图中心", latitude: mapView.centerCoordinate.latitude, longitude: mapView.centerCoordinate.longitude)
        )
    }

    private func configureMap() {
        mapView.delegate = self
        mapView.showsCompass = true
        mapView.showsScale = true
        if #available(iOS 13.0, *) {
            mapView.pointOfInterestFilter = .includingAll
        }
        mapView.setRegion(
            MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 31.2304, longitude: 121.4737),
                latitudinalMeters: 5000,
                longitudinalMeters: 5000
            ),
            animated: false
        )

        centerPin.text = "⌖"
        centerPin.textAlignment = .center
        centerPin.textColor = .systemRed
        centerPin.font = .systemFont(ofSize: 34, weight: .semibold)
    }

    private func configureSearch() {
        searchBar.delegate = self
        searchBar.placeholder = "搜索地名或地址"
        searchBar.searchBarStyle = .minimal
        searchBar.backgroundImage = UIImage()

        completer.delegate = self
        if #available(iOS 13.0, *) {
            completer.resultTypes = [.address, .pointOfInterest]
        }

        suggestionsTable.dataSource = self
        suggestionsTable.delegate = self
        suggestionsTable.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        suggestionsTable.layer.cornerRadius = 10
        suggestionsTable.clipsToBounds = true
        suggestionsTable.isHidden = true
    }

    private func configureBottomPanel() {
        bottomPanel.layer.cornerRadius = 18
        bottomPanel.clipsToBounds = true

        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.numberOfLines = 1

        detailLabel.font = .systemFont(ofSize: 13)
        detailLabel.textColor = .darkGray
        detailLabel.numberOfLines = 2

        coordinateLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        coordinateLabel.textColor = .darkGray

        configureButton(lockButton, title: "锁定位置", action: #selector(lockCurrentPlace))
        configureButton(favoriteButton, title: "收藏", action: #selector(addFavorite))
        configureButton(favoritesButton, title: "收藏夹", action: #selector(openFavorites))
        configureButton(tutorialButton, title: "教程", action: #selector(openTutorial))
    }

    private func configureButton(_ button: UIButton, title: String, action: Selector) {
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        button.backgroundColor = UIColor(white: 0.95, alpha: 1.0)
        button.layer.cornerRadius = 10
        button.contentEdgeInsets = UIEdgeInsets(top: 11, left: 12, bottom: 11, right: 12)
        button.addTarget(self, action: action, for: .touchUpInside)
    }

    private func layoutViews() {
        view.addSubview(mapView)
        view.addSubview(centerPin)
        view.addSubview(searchBar)
        view.addSubview(suggestionsTable)
        view.addSubview(bottomPanel)

        mapView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        centerPin.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.width.height.equalTo(48)
        }
        searchBar.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide).offset(8)
            make.leading.trailing.equalToSuperview().inset(12)
            make.height.equalTo(48)
        }
        suggestionsTable.snp.makeConstraints { make in
            make.top.equalTo(searchBar.snp.bottom).offset(4)
            make.leading.trailing.equalTo(searchBar)
            make.height.equalTo(190)
        }
        bottomPanel.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(12)
            make.bottom.equalTo(view.safeAreaLayoutGuide).inset(12)
        }

        let buttonRow = UIStackView(arrangedSubviews: [lockButton, favoriteButton, favoritesButton, tutorialButton])
        buttonRow.axis = .horizontal
        buttonRow.spacing = 8
        buttonRow.distribution = .fillEqually

        let stack = UIStackView(arrangedSubviews: [titleLabel, detailLabel, coordinateLabel, buttonRow])
        stack.axis = .vertical
        stack.spacing = 8
        bottomPanel.contentView.addSubview(stack)
        stack.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(14)
        }
    }

    private func updateSelectedPlace(_ place: WLocPlace) {
        selectedPlace = place
        titleLabel.text = place.name
        detailLabel.text = place.detail.isEmpty ? "移动地图微调位置，或搜索一个地名" : place.detail
        coordinateLabel.text = place.coordinateText
        favoriteButton.isEnabled = !WLocFavoriteStore.shared.contains(place)
        favoriteButton.setTitle(favoriteButton.isEnabled ? "收藏" : "已收藏", for: .normal)
    }

    private func moveMap(to place: WLocPlace) {
        mapView.setRegion(
            MKCoordinateRegion(center: place.coordinate, latitudinalMeters: 700, longitudinalMeters: 700),
            animated: true
        )
        updateSelectedPlace(place)
        mapView.removeAnnotations(mapView.annotations)
        let annotation = MKPointAnnotation()
        annotation.title = place.name
        annotation.subtitle = place.detail
        annotation.coordinate = place.coordinate
        mapView.addAnnotation(annotation)
    }

    private func refreshPlaceForMapCenter() {
        let coordinate = mapView.centerCoordinate
        let fallback = WLocPlace(name: "地图中心", latitude: coordinate.latitude, longitude: coordinate.longitude)
        updateSelectedPlace(fallback)

        reverseGeocodeWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.geocoder.cancelGeocode()
            self.geocoder.reverseGeocodeLocation(CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)) { placemarks, _ in
                guard let placemark = placemarks?.first else { return }
                let name = placemark.name ?? "地图中心"
                let detail = [placemark.locality, placemark.administrativeArea, placemark.country]
                    .compactMap { $0 }
                    .joined(separator: " ")
                self.updateSelectedPlace(WLocPlace(name: name, detail: detail, latitude: coordinate.latitude, longitude: coordinate.longitude))
            }
        }
        reverseGeocodeWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: workItem)
    }

    @objc private func lockCurrentPlace() {
        guard let place = selectedPlace else { return }
        setBusy(true, title: "锁定中...")
        vpnManager.lock(to: place) { [weak self] result in
            DispatchQueue.main.async {
                self?.setBusy(false, title: "锁定位置")
                switch result {
                case .success:
                    self?.showMessage("已锁定", "已保存目标位置，请按教程刷新定位服务。")
                    self?.lockButton.setTitle("解锁还原", for: .normal)
                    self?.lockButton.removeTarget(nil, action: nil, for: .touchUpInside)
                    self?.lockButton.addTarget(self, action: #selector(WLocMapViewController.unlockLocation), for: .touchUpInside)
                case .failure(let error):
                    self?.showMessage("启动失败", error.localizedDescription)
                }
            }
        }
    }

    @objc private func unlockLocation() {
        vpnManager.disable { [weak self] error in
            DispatchQueue.main.async {
                if let error {
                    self?.showMessage("还原失败", error.localizedDescription)
                } else {
                    self?.showMessage("已还原", "增强定位已关闭。")
                    self?.lockButton.setTitle("锁定位置", for: .normal)
                    self?.lockButton.removeTarget(nil, action: nil, for: .touchUpInside)
                    self?.lockButton.addTarget(self, action: #selector(WLocMapViewController.lockCurrentPlace), for: .touchUpInside)
                }
            }
        }
    }

    @objc private func addFavorite() {
        guard let place = selectedPlace else { return }
        WLocFavoriteStore.shared.add(place)
        updateSelectedPlace(place)
    }

    @objc private func openFavorites() {
        let controller = WLocFavoritesViewController()
        controller.onSelect = { [weak self] place in
            self?.navigationController?.popViewController(animated: true)
            self?.moveMap(to: place)
        }
        navigationController?.pushViewController(controller, animated: true)
    }

    @objc private func openTutorial() {
        let controller = WLocTutorialViewController()
        let navigation = UINavigationController(rootViewController: controller)
        present(navigation, animated: true)
    }

    private func setBusy(_ busy: Bool, title: String) {
        lockButton.isEnabled = !busy
        lockButton.setTitle(title, for: .normal)
    }

    private func showMessage(_ title: String, _ message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .default))
        present(alert, animated: true)
    }
}

extension WLocMapViewController: UISearchBarDelegate {
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        completer.region = mapView.region
        completer.queryFragment = searchText
        suggestionsTable.isHidden = searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }
}

extension WLocMapViewController: MKLocalSearchCompleterDelegate {
    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        searchResults = Array(completer.results.prefix(12))
        suggestionsTable.reloadData()
        suggestionsTable.isHidden = searchResults.isEmpty
    }
}

extension WLocMapViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        searchResults.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let result = searchResults[indexPath.row]
        cell.textLabel?.numberOfLines = 2
        cell.textLabel?.text = result.subtitle.isEmpty ? result.title : "\(result.title)\n\(result.subtitle)"
        cell.textLabel?.font = .systemFont(ofSize: 15)
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let completion = searchResults[indexPath.row]
        let request = MKLocalSearch.Request(completion: completion)
        request.region = mapView.region
        MKLocalSearch(request: request).start { [weak self] response, error in
            guard let self else { return }
            if let item = response?.mapItems.first {
                self.moveMap(to: WLocPlace(mapItem: item))
            } else if let error {
                self.showMessage("搜索失败", error.localizedDescription)
            }
        }
        searchBar.text = completion.title
        searchBar.resignFirstResponder()
        suggestionsTable.isHidden = true
    }
}

extension WLocMapViewController: MKMapViewDelegate {
    func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
        refreshPlaceForMapCenter()
    }
}
