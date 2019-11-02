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
    @IBOutlet weak var playButton: UIButton!
    
    private var isViewAppearedAtLeastOnce: Bool = false;
    
    private let cloudServiceController = SKCloudServiceController()
    private let defaultArtwork : UIImage = UIImage()
    private var storefrontCountryCode : String? = nil
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // tableViewのdelegate, dataSource設定
        tableView.delegate = self
        tableView.dataSource = self
        
        let footerView = UIView()
        footerView.frame.size.height = tableView.rowHeight
        tableView.tableFooterView = footerView // 空のセルの罫線を消す
        
        playingArtwork.layer.cornerRadius = playingArtwork.frame.size.width * 0.05
        playingArtwork.clipsToBounds = true
        
        // Apple Musicライブラリへのアクセス許可の確認
        SKCloudServiceController.requestAuthorization { status in
            guard status == .authorized else { return }
            // Apple Musicの曲が再生可能か確認
            self.cloudServiceController.requestCapabilities { (capabilities, error) in
                guard error == nil && capabilities.contains(.musicCatalogPlayback) else { return }
            }
        }
        
        NotificationCenter.default.addObserver(self, selector: #selector(handleRequestsUpdated), name:
            .DJYusakuPlayerQueueDidUpdate, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handlePlayingItemChanged), name: .MPMusicPlayerControllerNowPlayingItemDidChange, object: nil)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        if !self.isViewAppearedAtLeastOnce {  // 初回だけ表示する画面遷移に使う
            // 初回にはWelcomeViewをモーダルを表示
            let storyboard: UIStoryboard = self.storyboard!
            let welcomNavigationController = storyboard.instantiateViewController(withIdentifier: "WelcomeNavigation")
            welcomNavigationController.isModalInPresentation = true
            self.present(welcomNavigationController, animated: true)
            
            // 2度目以降の表示はしない
            self.isViewAppearedAtLeastOnce = true
        }
    }
    
    @objc func handlePlayingItemChanged(notification: NSNotification){
        guard let nowPlayingSong = PlayerQueue.shared.get(at: 0) else { return }
        // PlayerQueue.shared.remove(at: 0)
        
        DispatchQueue.global().async {
            let fetchedImage = Artwork.fetch(url: nowPlayingSong.artworkUrl)
            DispatchQueue.main.async {
                self.tableView.reloadData()
                self.playingTitle.text    = nowPlayingSong.title
                self.playingArtwork.image = fetchedImage
            }
        }
    }
    
    @objc func handleRequestsUpdated(notification: NSNotification){
        DispatchQueue.main.async{
            self.tableView.reloadData()
        }
    }
    
    @IBAction func playButton(_ sender: Any) {
        if PlayerQueue.shared.mpAppController.playbackState != .playing{
            PlayerQueue.shared.mpAppController.play()
            playButton.setImage(UIImage(systemName: "playpause.fill"), for: UIControl.State.normal)
        }
    }
    
    @IBAction func skipButton(_ sender: Any) {
        PlayerQueue.shared.mpAppController.skipToNextItem()
    }
    
}

// MARK: - UITableViewDataSource

extension RequestsViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let count = PlayerQueue.shared.count() == 0 ? 0 : PlayerQueue.shared.count() - 1
        return count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "RequestsMusicTableViewCell", for: indexPath) as! RequestsMusicTableViewCell
        
        guard let item = PlayerQueue.shared.get(at: indexPath.row + 1) else { return cell  }
        
        cell.title.text    = item.title
        cell.artist.text   = item.artist
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
            PlayerQueue.shared.remove(at: indexPath.row + 1)
            tableView.deleteRows(at: [indexPath], with: .fade)
        }
    }
}
