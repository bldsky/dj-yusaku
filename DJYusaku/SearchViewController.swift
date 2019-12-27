//
//  SearchViewController.swift
//  DJYusaku
//
//  Created by Hayato Kohara on 2019/10/12.
//  Copyright © 2019 Yusaku. All rights reserved.
//

import UIKit
import StoreKit
import SwiftyJSON

class SearchViewController: UIViewController {
    @IBOutlet weak var tableView: UITableView!
    @IBOutlet weak var viewWhenNoSearchWords: UIView!
    @IBOutlet weak var viewWhenNoSearchResults: UIView!
    
    private let searchController = UISearchController(searchResultsController: nil)
    private let cloudServiceController = SKCloudServiceController()
    private var storefrontCountryCode : String? = nil
    private var results : [Song] = []
    private let defaultArtwork : UIImage = UIImage()
    // 画像の取得の際に用いるキュー
    private let imageFetchQueue = DispatchQueue(label: "DJYusakuImageFetch", qos:.userInteractive)
    private var imageFetchWorkItem : [DispatchWorkItem?] = [DispatchWorkItem?](repeating: nil, count: 25)
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        viewWhenNoSearchWords.isHidden   = false
        viewWhenNoSearchResults.isHidden = true
        
        // 検索バーの設定
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "Songs, Artists, Lyrics, and More"
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        
        // tableViewのdelegate, dataSource設定
        tableView.delegate = self
        tableView.dataSource = self
        tableView.tableFooterView = UIView() // 空のセルの罫線を消す
        
        // Apple Musicのロケール設定
        self.cloudServiceController.requestStorefrontCountryCode { (storefrontCountryCode, error) in
            if error != nil {
                // アラートを表示
                let alertController = UIAlertController(title:   "Apple Music connection failed",
                                                        message: "Please check your iCloud account status.",
                                                        preferredStyle: UIAlertController.Style.alert)
                let alertButton = UIAlertAction(title: "OK",
                                                style: UIAlertAction.Style.cancel,
                                                handler: nil)
                alertController.addAction(alertButton)
                self.present(alertController, animated: true, completion: nil)
                return
            }
            self.storefrontCountryCode = storefrontCountryCode
        }
    }
    
    @IBAction func closeButton(_ sender: Any) {
        self.dismiss(animated: true)
    }
    
}

// MARK: - UITableViewDataSource

extension SearchViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return results.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "SearchMusicTableViewCell", for: indexPath) as! SearchMusicTableViewCell
        
        let item = results[indexPath.row]
        cell.title.text       = item.title
        cell.artist.text      = item.artist
        cell.artwork.image    = defaultArtwork
        
        self.imageFetchWorkItem[indexPath.row]?.cancel()
        self.imageFetchWorkItem[indexPath.row] = DispatchWorkItem {
            let image = CachedImage.fetch(url: item.artworkUrl)
            DispatchQueue.main.async {
                cell.artwork.image = image  // 画像の取得に失敗していたらnilが入ることに注意
                cell.artwork.setNeedsLayout()
            }
        }
        imageFetchQueue.async(execute: self.imageFetchWorkItem[indexPath.row]!)
        
        return cell
    }
}

// MARK: - UITableViewDelegate

extension SearchViewController: UITableViewDelegate {
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        self.tableView.deselectRow(at: indexPath, animated: false)  // セルの選択を解除
        
        let song = results[indexPath.row]
        let viewController = self.presentingViewController ?? self   // 閉じる対象のViewController
        if ConnectionController.shared.isDJ! {   // 自分がDJのとき
            PlayerQueue.shared.add(with: song) { [unowned viewController] in
                viewController.dismiss(animated: true)    // 1曲追加するごとにViewを閉じる
            }
        } else {                                 // 自分がリスナーのとき
            guard ConnectionController.shared.connectedDJ!.state == .connected else { return }
            let songData = try! JSONEncoder().encode(song)
            
            let messageData = try! JSONEncoder().encode(MessageData(desc:  MessageData.DataType.requestSong, value: songData))
            
            ConnectionController.shared.session.sendRequest(messageData, toPeers: [ConnectionController.shared.connectedDJ!.peerID], with: .unreliable) { [unowned viewController] in
                viewController.dismiss(animated: true)    // 1曲追加するごとにViewを閉じる
            }
        }
    }
    
}
    
// MARK: - UISearchResultsUpdating

extension SearchViewController: UISearchResultsUpdating {
    
    // Apple Musicに検索クエリを投げる
    func search(storeFront: String, term: String, limit: Int, types: String, completion: @escaping (JSON?) -> Void) {
        guard 1...25 ~= limit else { // Apple Musicの検索は一度に25件まで
            completion(nil)
            return
        }
        
        // 検索用URLの作成
        var endpoint : URL
        var urlComponents = URLComponents(string: "https://api.music.apple.com/v1/catalog/\(storeFront)/search")!
        urlComponents.queryItems = [
            URLQueryItem(name: "term", value: term),                    // 検索キーワード
            URLQueryItem(name: "limit", value: limit.description),      // 取得件数 (最大25件)
            URLQueryItem(name: "types", value: types),                  // 検索種別 (複数可能)
        ]
        endpoint = urlComponents.url!
        
        // GETリクエスト作成
        var request = URLRequest(url: endpoint)
        request.addValue("Bearer \(Secrets.AppleMusicDeveloperToken)", forHTTPHeaderField: "Authorization")
        let task = URLSession.shared.dataTask(with: request) { (data, _, error) in
            guard error == nil, let data = data else { return }
            do {
                completion((try JSON(data: data))["results"][types]["data"])
            } catch {
                completion(nil)
            }
        }
        // 検索の実行
        task.resume()
    }
    
    func updateSearchResults(for searchController: UISearchController) {
        // 検索文字列の取得
        let searchText = searchController.searchBar.text ?? ""
        if searchText.isEmpty { // 空なら検索しない
            DispatchQueue.main.async {
                self.viewWhenNoSearchWords.isHidden   = false
                self.viewWhenNoSearchResults.isHidden = true
                self.results.removeAll()
                self.tableView.reloadData()
            }
            return
        }
        
        guard let storeFront = self.storefrontCountryCode else { return } // ロケール取得に失敗していたら何もしない
        
        // 検索を実行して画面を更新
        search(storeFront:storeFront, term:searchText, limit:25, types:"songs") { [unowned self] result in
            guard let songs = result else {
                print("Cannot GET json")
                return
            }
            
            DispatchQueue.main.async {
                // ダイアログ表示をかくす
                self.viewWhenNoSearchWords.isHidden   = true
                self.viewWhenNoSearchResults.isHidden = !songs.isEmpty
                
                // 今のsearchBarの内容と矛盾していれば何もしない
                let currentText = searchController.searchBar.text
                guard searchText == currentText else { return }
                
                self.results.removeAll()
                for (_, song):(String, JSON) in songs {
                    let title            = song["attributes"]["name"].stringValue
                    let artist           = song["attributes"]["artistName"].stringValue
                    let artworkUrlString = song["attributes"]["artwork"]["url"].stringValue
                    let songID           = song["attributes"]["playParams"]["id"].stringValue
                    let artworkUrl = CachedImage.url(urlString: artworkUrlString, width: 256, height: 256)
                    self.results.append(Song(title: title, artist: artist, artworkUrl: artworkUrl, id: songID, profileImageUrl: DefaultsController.shared.profile.imageUrl))
                }
                self.tableView.reloadData()
            }
        }
    }
}

// MARK: - UIBarPositioningDelegate

extension SearchViewController: UIBarPositioningDelegate {
    func position(for bar: UIBarPositioning) -> UIBarPosition {
        return UIBarPosition.topAttached;
    }

}
