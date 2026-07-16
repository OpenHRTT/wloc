import UIKit

final class WLocFavoritesViewController: UITableViewController {
    var onSelect: ((AppWLocPlace) -> Void)?
    private var places: [AppWLocPlace] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "收藏夹"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "favorite")
        reload()
    }

    private func reload() {
        places = AppWLocFavoriteStore.shared.all()
        tableView.reloadData()
        if places.isEmpty {
            let label = UILabel()
            label.text = "还没有收藏地点"
            label.textColor = .darkGray
            label.textAlignment = .center
            tableView.backgroundView = label
        } else {
            tableView.backgroundView = nil
        }
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        places.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "favorite", for: indexPath)
        let place = places[indexPath.row]
        cell.textLabel?.numberOfLines = 3
        cell.selectionStyle = .none
        cell.textLabel?.text = "\(place.name)\n\(place.detail)\n\(place.coordinateText)"
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        onSelect?(places[indexPath.row])
    }

    override func tableView(
        _ tableView: UITableView,
        commit editingStyle: UITableViewCell.EditingStyle,
        forRowAt indexPath: IndexPath
    ) {
        guard editingStyle == .delete else { return }
        AppWLocFavoriteStore.shared.remove(id: places[indexPath.row].id)
        reload()
    }
}
