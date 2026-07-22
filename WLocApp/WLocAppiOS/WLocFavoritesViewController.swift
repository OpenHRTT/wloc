import UIKit

final class WLocFavoritesViewController: UITableViewController {
    var onSelect: ((AppWLocPlace) -> Void)?
    private var favorites: [AppWLocFavorite] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "收藏夹"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "favorite")
        tableView.rowHeight = 96
        reload()
    }

    private func reload() {
        favorites = AppWLocFavoriteStore.shared.all()
        tableView.reloadData()
        if favorites.isEmpty {
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
        favorites.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "favorite", for: indexPath)
        let favorite = favorites[indexPath.row]
        cell.textLabel?.numberOfLines = 4
        cell.textLabel?.font = .systemFont(ofSize: 13)
        cell.selectionStyle = .none
        cell.textLabel?.text = [
            "别名：\(favorite.displayAlias)",
            "地点：\(favorite.title)",
            "地址：\(favorite.displayDetail)",
            "坐标：\(favorite.coordinateText)"
        ].joined(separator: "\n")
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        onSelect?(favorites[indexPath.row].place)
    }

    override func tableView(
        _ tableView: UITableView,
        commit editingStyle: UITableViewCell.EditingStyle,
        forRowAt indexPath: IndexPath
    ) {
        guard editingStyle == .delete else { return }
        AppWLocFavoriteStore.shared.remove(id: favorites[indexPath.row].id)
        reload()
    }
}
