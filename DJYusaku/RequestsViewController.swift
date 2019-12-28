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

extension Notification.Name {
    static let DJYusakuRequestVCDidEnterBackground = Notification.Name("DJYusakuRequestVCDidEnterBackground")
    static let DJYusakuRequestVCWillEnterForeground = Notification.Name("DJYusakuRequestVCWillEnterForeground")
}
class RequestsViewController: UIViewController {
    @IBOutlet weak var tableView: UITableView!
    @IBOutlet weak var playButton: UIButton!
    @IBOutlet weak var skipButton: UIButton!
    @IBOutlet weak var batterySaverButton: UIButton!
    @IBOutlet weak var noRequestsView: UIView!
    
    @IBOutlet weak var playerControllerView: UIView!
    @IBOutlet weak var playButtonBackgroundView: UIView!
    
    static private var isViewAppearedAtLeastOnce: Bool = false
    static private var indexOfNowPlayingItemOnListener: Int = 0
    
    private let cloudServiceController = SKCloudServiceController()
    private let defaultArtwork : UIImage = UIImage()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        tableView.dataSource = self
        tableView.delegate   = self
        
        // 再生コントロールの見た目を設定（角丸・影・境界線など）
        
        playerControllerView.isHidden               = true //初めは隠しておく
        playerControllerView.layer.cornerRadius     = playerControllerView.frame.size.height * 0.5
        playerControllerView.layer.shadowColor      = CGColor(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 1.0)
        playerControllerView.layer.shadowOffset     = .zero
        playerControllerView.layer.shadowOpacity    = 0.4
        playerControllerView.layer.borderColor      = CGColor(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 0.3)
        playerControllerView.layer.borderWidth      = 1

        playButtonBackgroundView.layer.cornerRadius = playButtonBackgroundView.frame.size.height * 0.5
        
        playButton.isEnabled = false
        skipButton.isEnabled = false

        let footerView = UIView()
        footerView.frame.size.height = 100
        tableView.tableFooterView = footerView // 空のセルの罫線を消す
        
        // Apple Musicライブラリへのアクセス許可の確認
        SKCloudServiceController.requestAuthorization { status in
            guard status == .authorized else { return }
            // Apple Musicの曲が再生可能か確認
            self.cloudServiceController.requestCapabilities { (capabilities, error) in
                guard error == nil && capabilities.contains(.musicCatalogPlayback) else { return }
            }
        }
        
        NotificationCenter.default.addObserver(self, selector: #selector(handleRequestsDidUpdate), name: .DJYusakuPlayerQueueDidUpdate, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleNowPlayingItemDidChangeOnDJ), name: .DJYusakuPlayerQueueNowPlayingSongDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handlePlaybackStateDidChange), name: .DJYusakuPlayerQueuePlaybackStateDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleNowPlayingItemDidChangeOnListener), name: .DJYusakuConnectionControllerNowPlayingSongDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handlePlayerControllerViewFromUserState), name: .DJYusakuUserStateDidUpdate, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleButtonStateChange), name: .DJYusakuIsQueueCreatedDidChange, object: nil)
        
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        if !RequestsViewController.isViewAppearedAtLeastOnce {  // 初回だけ表示する画面遷移に使う
            // 初回にはWelcomeViewをモーダルを表示
            let storyboard: UIStoryboard = self.storyboard!
            let welcomeNavigationController = storyboard.instantiateViewController(withIdentifier: "WelcomeNavigation")
            welcomeNavigationController.isModalInPresentation = true
            self.present(welcomeNavigationController, animated: true)
        }
        RequestsViewController.isViewAppearedAtLeastOnce = true
        
        // TableViewの表示を更新する
        DispatchQueue.main.async {
            self.tableView.reloadData()
        }
        // スクロールを現在再生中の曲に移動する
        scrollToNowPlayingItem(animated: false)
    }
    
    @objc func handleRequestsDidUpdate(){
        guard let isDJ = ConnectionController.shared.isDJ else { return }
        DispatchQueue.main.async{
            if isDJ {
                self.noRequestsView.isHidden = !PlayerQueue.shared.songs.isEmpty
            }else{
                self.noRequestsView.isHidden = !ConnectionController.shared.receivedSongs.isEmpty
            }
            self.tableView.reloadData()
        }
    }
    
    @objc func handleNowPlayingItemDidChangeOnDJ(){
        
        DispatchQueue.main.async {
            self.tableView.reloadData()
        }
        
        guard ConnectionController.shared.session.connectedPeers.count != 0 else { return }
        
        let indexOfNowPlayingItemData = try! JSONEncoder().encode(PlayerQueue.shared.mpAppController.indexOfNowPlayingItem)
        let messageData = try! JSONEncoder().encode(MessageData(desc: MessageData.DataType.nowPlaying, value: indexOfNowPlayingItemData))
        do {
            try ConnectionController.shared.session.send(messageData, toPeers: ConnectionController.shared.session.connectedPeers, with: .unreliable)
        } catch let error {
            print(error)
        }
    }
    
    // （リスナーのとき）NowPlayingItemが変わったとき呼ばれる
    @objc func handleNowPlayingItemDidChangeOnListener(notification: NSNotification){
        guard let indexOfNowPlayingItem = notification.userInfo!["indexOfNowPlayingItem"] as? Int else { return }
        RequestsViewController.self.indexOfNowPlayingItemOnListener = indexOfNowPlayingItem
        DispatchQueue.main.async {
            self.tableView.reloadData()
        }
    }
    
    @objc func handlePlaybackStateDidChange(notification: NSNotification) {
        switch PlayerQueue.shared.mpAppController.playbackState {
        case .playing:
            playButton.setImage(UIImage(systemName: "pause.fill"), for: UIControl.State.normal)
        case .paused, .stopped:
            playButton.setImage(UIImage(systemName: "play.fill"), for: UIControl.State.normal)
        default:
            break
        }
    }
    
    @objc func handlePlayerControllerViewFromUserState() {
        guard let isDJ = ConnectionController.shared.isDJ else { return }
        self.playerControllerView.isHidden = !isDJ
    }
    
    @objc func handleButtonStateChange() {
        playButton.isEnabled = PlayerQueue.shared.isQueueCreated
        skipButton.isEnabled = PlayerQueue.shared.isQueueCreated
        DispatchQueue.main.async {
            self.noRequestsView.isHidden = PlayerQueue.shared.isQueueCreated
        }
        
        /*
         isDJ のT/Fは receivedSongs.isEmpty() のT/Fと同義
         isDJ: T (=DJ)
            -> isHidden のT/FはisQueueCreatedのT/Fと同義
         isDJ: F (=Listener)
            -> isHidden のT/FはreceivedSongs.isEmpty()のT/Fと同義
         */
    }
    
    func scrollToNowPlayingItem(animated: Bool = true) {
        guard ConnectionController.shared.isDJ != nil else { return }
        
        let numberOfRequestedSongs = ConnectionController.shared.isDJ!
                                   ? PlayerQueue.shared.count()
                                   : ConnectionController.shared.receivedSongs.count
        guard numberOfRequestedSongs != 0 else { return }
        
        let indexOfNowPlayingItem  = ConnectionController.shared.isDJ!
                                   ? PlayerQueue.shared.mpAppController.indexOfNowPlayingItem
                                   : RequestsViewController.self.indexOfNowPlayingItemOnListener
        DispatchQueue.main.async {
            let indexPath = IndexPath(row: indexOfNowPlayingItem, section: 0)
            self.tableView.scrollToRow(at: indexPath, at: UITableView.ScrollPosition.top, animated: animated)
        }
    }
    
    func animateShrinkDown(view: UIView, scale: CGFloat) {
        UIView.animate(withDuration: 0.05, delay: 0.0, animations: {
            view.transform = CGAffineTransform(scaleX: scale, y: scale);
        }, completion: { _ in
            view.transform = CGAffineTransform(scaleX: scale, y: scale);
        })
    }
    
    func animateGrowUp(view: UIView) {
        UIView.animate(withDuration: 0.05, delay: 0.0, animations: {
            view.transform = CGAffineTransform.identity;
        }, completion: { _ in
            view.transform = CGAffineTransform.identity;
        })
    }
    
    @IBAction func playButtonTouchDown(_ sender: Any) {
        // アニメーション
        animateShrinkDown(view: self.playButtonBackgroundView, scale: 0.9)
    }
    
    @IBAction func playButtonTouchUp(_ sender: Any) {
        // アニメーション
        animateGrowUp(view: self.playButtonBackgroundView)
        
        // 曲の再生・停止
        switch PlayerQueue.shared.mpAppController.playbackState {
        case .playing:          // 再生中なら停止する
            PlayerQueue.shared.mpAppController.pause()
        case .paused, .stopped: // 停止中なら再生する
            PlayerQueue.shared.mpAppController.play()
        default:
            break
        }
    }
    
    @IBAction func skipButtonTouchDown(_ sender: Any) {
        // アニメーション
        animateShrinkDown(view: self.skipButton, scale: 0.75)
    }
    
    @IBAction func skipButtonTouchUp(_ sender: Any) {
        // アニメーション
        animateGrowUp(view: self.skipButton)
        
        // 曲のスキップ
        PlayerQueue.shared.mpAppController.skipToNextItem()
    }
    
    @IBAction func batterySaverButtonTouchDown(_ sender: Any) {
        // アニメーション
        animateShrinkDown(view: self.batterySaverButton, scale: 0.75)
    }
    
    @IBAction func batterySaverButtonTouchUp(_ sender: Any) {
        // アニメーション
        animateGrowUp(view: self.batterySaverButton)
        
        // アラートを表示
        let alertController = UIAlertController(title:   "Battery Saver Mode",
                                                message: "To exit battery saver mode, double-tap the screen.",
                                                preferredStyle: UIAlertController.Style.alert)
        let alertButton = UIAlertAction(title: "OK", style: UIAlertAction.Style.cancel) { [unowned self] _ in
            let storyboard: UIStoryboard = self.storyboard!
            let batterySaverView = storyboard.instantiateViewController(withIdentifier: "BatterySaverView")
            batterySaverView.modalPresentationStyle = .fullScreen
            batterySaverView.modalTransitionStyle   = .crossDissolve
            self.present(batterySaverView, animated: true)
        }
        alertController.addAction(alertButton)
        self.present(alertController, animated: true)
    }
    
    @IBAction func reloadButton(_ sender: Any) {
        DispatchQueue.main.async {
            self.tableView.reloadData()
        }
        scrollToNowPlayingItem()
    }
}

// MARK: - UITableViewDataSource

extension RequestsViewController: UITableViewDataSource {
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard ConnectionController.shared.isDJ != nil else { return 0 }
        if ConnectionController.shared.isDJ! {
            return PlayerQueue.shared.count()
        } else {
            return ConnectionController.shared.receivedSongs.count
        }
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "RequestsMusicTableViewCell", for: indexPath) as! RequestsMusicTableViewCell
        var song: Song
        if ConnectionController.shared.isDJ! {
            guard let queueSong = PlayerQueue.shared.get(at: indexPath.row) else { return cell }
            song = queueSong
        } else {
            song = ConnectionController.shared.receivedSongs[indexPath.row]
        }
        
        let indexOfNowPlayingItem = ConnectionController.shared.isDJ!
                                  ? PlayerQueue.shared.mpAppController.indexOfNowPlayingItem
                                  : RequestsViewController.self.indexOfNowPlayingItemOnListener
        cell.title.text    = song.title
        cell.artist.text   = song.artist
        if let profileImageUrl = song.profileImageUrl {
            cell.profileImageView.image = CachedImage.fetch(url: profileImageUrl)
        }
        cell.nowPlayingIndicator.isHidden = indexOfNowPlayingItem != indexPath.row
        
        DispatchQueue.global().async {
            let image = CachedImage.fetch(url: song.artworkUrl)
            DispatchQueue.main.async {
                cell.artwork.image = image  // 画像の取得に失敗していたらnilが入ることに注意
                cell.artwork.setNeedsLayout()
            }
        }
        if (indexPath.row < indexOfNowPlayingItem) {
            cell.title.alpha    = 0.3
            cell.artist.alpha   = 0.3
            cell.artwork.alpha  = 0.3
        } else {
            cell.title.alpha    = 1.0
            cell.artist.alpha   = 1.0
            cell.artwork.alpha  = 1.0
        }
        
        return cell
    }
    
    // 編集・削除機能を無効にする
    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        return false
    }
}

// MARK: - UITableViewDelegate

extension RequestsViewController: UITableViewDelegate {
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        self.tableView.deselectRow(at: indexPath, animated: false)  // セルの選択を解除
        if ConnectionController.shared.isDJ! {   // 自分がDJのとき
            // 曲を再生する
            PlayerQueue.shared.play(at: indexPath.row)
        }
    }
    
}
