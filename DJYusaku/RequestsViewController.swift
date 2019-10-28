//
//  RequestsViewController.swift
//  DJYusaku
//
//  Created by Hayato Kohara on 2019/10/05.
//  Copyright © 2019 Yusaku. All rights reserved.
//

import UIKit
import StoreKit
import MediaPlayer

class RequestsViewController: UIViewController {
    @IBOutlet weak var tableView: UITableView!
    @IBOutlet weak var playingArtwork: UIImageView!
    @IBOutlet weak var playingTitle: UILabel!
    
    private let cloudServiceController = SKCloudServiceController()
    private let defaultArtwork : UIImage = UIImage()
    private var storefrontCountryCode : String? = nil
    private var mediaItems: [MPMediaItem] = []
    
    private let musicPlayerApplicationController = MPMusicPlayerController.applicationQueuePlayer
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // tableViewのdelegate, dataSource設定
        tableView.delegate = self
        tableView.dataSource = self
        
        // Apple Musicライブラリへのアクセス許可の確認
        SKCloudServiceController.requestAuthorization { status in
            guard status == .authorized else { return }
            // Apple Musicの曲が再生可能か確認
            self.cloudServiceController.requestCapabilities { (capabilities, error) in
                guard error == nil && capabilities.contains(.musicCatalogPlayback) else { return }
            }
            
        }

        
        let footerView = UIView()
        footerView.frame.size.height = tableView.rowHeight
        tableView.tableFooterView = footerView // 空のセルの罫線を消す
        
        playingArtwork.layer.cornerRadius = playingArtwork.frame.size.width * 0.05
        playingArtwork.clipsToBounds = true
        
        NotificationCenter.default.addObserver(self, selector: #selector(handleRequestsUpdated), name: .requestQueueToRequestsVCName, object: nil)
    }
    
    @objc func handleRequestsUpdated(notification: NSNotification){
        // リクエスト画面を更新
        DispatchQueue.main.async{
            self.tableView.reloadData()
        }
        // TODO: [amylase] insertMusicPlayerControllerQueueを呼び出す
        // リクエストが完了した旨のAlertを表示
        guard let title = notification.userInfo!["title"] as? String else { return }
        
        let alert = UIAlertController(title: title, message: "was Requested", preferredStyle: UIAlertController.Style.alert)

        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))

        present(alert, animated: true)
    }
    
    
    func insertMusicPlayerControllerQueue(persistentID : UInt64){
        musicPlayerApplicationController.perform(queueTransaction: { mutableQueue in
            let predicate = MPMediaPropertyPredicate(value: persistentID,
                                                     forProperty: MPMediaItemPropertyPersistentID)
            
            let query = MPMediaQuery(filterPredicates: [predicate])
            let descripter = MPMusicPlayerMediaItemQueueDescriptor(query: query)
            
            mutableQueue.insert(descripter, after: mutableQueue.items.last)
            
            //ボタンを追加するまで、queueに曲が追加されたら再生を始めるものとする
            //エラーは考えない
            if (self.musicPlayerApplicationController.playbackState != .playing){
                self.musicPlayerApplicationController.play()
            }
        }, completionHandler: { queue, error in
            if (error != nil){
                print("insert error.")
                // TODO: キューへの追加ができなかった時の処理を記述
            }
        })
    }
}

// MARK: - UITableViewDataSource

extension RequestsViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return RequestQueue.shared.countRequests()
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "RequestsMusicTableViewCell", for: indexPath) as! RequestsMusicTableViewCell
        
        let item = RequestQueue.shared.getRequest(index: indexPath.row)
        cell.title.text = item.title
        cell.artist.text = item.artist
        cell.artwork.image = defaultArtwork
        
        DispatchQueue.global().async {
            let fetchedImage = Artwork.fetch(url: item.artworkUrl)
            DispatchQueue.main.async {
                cell.artwork.image = fetchedImage // 画像の取得に失敗していたらnilが入ることに注意
                cell.artwork.setNeedsLayout()
            }
        }
        
        return cell
    }
}

// MARK: - UITableViewDelegate

extension RequestsViewController: UITableViewDelegate {
    // セルの編集時の挙動
    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            RequestQueue.shared.removeRequest(index: indexPath.row)
            tableView.deleteRows(at: [indexPath], with: .fade)
            //TODO: playerのqueueの中も削除
        }
    }
}
