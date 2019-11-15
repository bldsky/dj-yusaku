//
//  PlayerQueue.swift
//  DJYusaku
//
//  Created by Yuu Ichikawa on 2019/10/24.
//  Copyright © 2019 Yusaku. All rights reserved.
//

import Foundation
import UIKit
import MediaPlayer

extension Notification.Name {
    // MPMusicPlayerControllerによる通知をこちらで一旦引き受けることでタイミングを制御できるようにする
    static let DJYusakuPlayerQueueDidUpdate = Notification.Name("DJYusakuPlayerQueueDidUpdate")
    static let DJYusakuPlayerQueueNowPlayingSongDidChange = Notification.Name("DJYusakuPlayerQueueNowPlayingSongDidChange")
    static let DJYusakuPlayerQueuePlaybackStateDidChange = Notification.Name("DJYusakuPlayerQueuePlaybackStateDidChange")
}

class PlayerQueue{
    static let shared = PlayerQueue()
    let mpAppController = MPMusicPlayerController.applicationQueuePlayer
    
    private var items: [MPMediaItem] = []
    private var isQueueCreated: Bool = false
    
    private let dispatchSemaphore = DispatchSemaphore(value: 1)
    
    private init(){
        mpAppController.repeatMode = MPMusicRepeatMode.all
        NotificationCenter.default.addObserver(self, selector: #selector(handleNowPlayingItemDidChange), name: .MPMusicPlayerControllerNowPlayingItemDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handlePlaybackStateDidChange), name: .MPMusicPlayerControllerPlaybackStateDidChange, object: nil)
    }
    
    @objc func handleNowPlayingItemDidChange(){
        NotificationCenter.default.post(name: .DJYusakuPlayerQueueNowPlayingSongDidChange, object: nil)
    }
    
    @objc func handlePlaybackStateDidChange(){
        NotificationCenter.default.post(name: .DJYusakuPlayerQueuePlaybackStateDidChange, object: nil)
    }
    
    private func create(with song : Song, completion: (() -> (Void))? = nil) {
        guard self.dispatchSemaphore.wait(timeout: .now() + 4.0) != .timedOut else {
            // 前のキューへの追加処理が時間内に終わっていなければとりあえずリクエストを捨てる
            DispatchQueue.main.async {
                guard let rootViewController = (UIApplication.shared.windows.filter{$0.isKeyWindow}.first)?.rootViewController else { return }
                let alert = UIAlertController(title: "Request failed", message: "Queue insertion failed. Try again.", preferredStyle: UIAlertController.Style.alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
                rootViewController.present(alert, animated: true)
            }
            return
        }
        
        self.mpAppController.setQueue(with: [song.id])
        self.mpAppController.prepareToPlay() { [unowned self] error in
            defer {
                self.dispatchSemaphore.signal()
            }
            guard error == nil else { return } // TODO: キューの作成ができなかった時の処理
            self.mpAppController.play() // 自動再生する
            self.mpAppController.perform(queueTransaction: { _ in }, completionHandler: { [unowned self] queue, _ in
                self.items = queue.items
            })
            self.isQueueCreated = true
            if let completion = completion { completion() }
            NotificationCenter.default.post(name: .DJYusakuPlayerQueueDidUpdate, object: nil)
        }
    }

    private func insert(after index: Int, with song : Song, completion: (() -> (Void))? = nil){
        guard self.dispatchSemaphore.wait(timeout: .now() + 4.0) != .timedOut else {
            // 前のキューへの追加処理が時間内に終わっていなければとりあえずリクエストを捨てる
            DispatchQueue.main.async {
                guard let rootViewController = (UIApplication.shared.windows.filter{$0.isKeyWindow}.first)?.rootViewController else { return }
                let alert = UIAlertController(title: "Request failed", message: "Queue insertion failed. Try again.", preferredStyle: UIAlertController.Style.alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
                rootViewController.present(alert, animated: true)
            }
            return
        }
        
        self.mpAppController.perform(queueTransaction: { mutableQueue in
            let descripter = MPMusicPlayerStoreQueueDescriptor(storeIDs: [song.id])
            let insertItem = mutableQueue.items.count == 0 ? nil : mutableQueue.items[index]
            mutableQueue.insert(descripter, after: insertItem)
        }, completionHandler: { [unowned self] queue, error in
            defer {
                self.dispatchSemaphore.signal()
            }
            guard (error == nil) else { return } // TODO: 挿入ができなかった時の処理
            self.items = queue.items
            if let completion = completion { completion() }
            NotificationCenter.default.post(name: .DJYusakuPlayerQueueDidUpdate, object: nil)
        })
    }
    
    func remove(at index: Int, completion: (() -> (Void))? = nil) {
        guard self.dispatchSemaphore.wait(timeout: .now() + 4.0) != .timedOut else {
            // 前のキューへの追加処理が時間内に終わっていなければとりあえずリクエストを捨てる
            DispatchQueue.main.async {
                guard let rootViewController = (UIApplication.shared.windows.filter{$0.isKeyWindow}.first)?.rootViewController else { return }
                let alert = UIAlertController(title: "Deletion failed", message: "Queue deletion failed. Try again.", preferredStyle: UIAlertController.Style.alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
                rootViewController.present(alert, animated: true)
            }
            return
        }
        
        self.mpAppController.perform(queueTransaction: {mutableQueue in
            mutableQueue.remove(mutableQueue.items[index])
        }, completionHandler: { [unowned self] queue, error in
            defer {
                self.dispatchSemaphore.signal()
            }
            guard (error == nil) else { return } // TODO: 削除ができなかった時の処理
            self.items = queue.items
            if let completion = completion { completion() }
            NotificationCenter.default.post(name: .DJYusakuPlayerQueueDidUpdate, object: nil)
        })
    }
    
    func swap(from: Int, to: Int, completion: (() -> (Void))? = nil){
        
        let swappedItem = items[from]
        guard self.dispatchSemaphore.wait(timeout: .now() + 4.0) != .timedOut else {
            // 前のキューへの追加処理が時間内に終わっていなければとりあえずリクエストを捨てる
            DispatchQueue.main.async {
                guard let rootViewController = (UIApplication.shared.windows.filter{$0.isKeyWindow}.first)?.rootViewController else { return }
                let alert = UIAlertController(title: "Swap failed", message: "Swap failed. Try again.", preferredStyle: UIAlertController.Style.alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
                rootViewController.present(alert, animated: true)
            }
            return
        }
        
        // 対象リクエストの削除
        self.mpAppController.perform(queueTransaction: {mutableQueue in
            mutableQueue.remove(swappedItem)
        }, completionHandler: { [unowned self] queue, error in
            guard (error == nil) else {
                self.dispatchSemaphore.signal()
                print("Delete Failed")
                return
            } // TODO: 削除ができなかった時の処理
            if let completion = completion { completion() }
            NotificationCenter.default.post(name: .DJYusakuPlayerQueueDidUpdate, object: nil)
    
            //対象リクエストの再挿入
            self.mpAppController.perform(queueTransaction: { mutableQueue in
                let descripter = MPMusicPlayerStoreQueueDescriptor(storeIDs: [String(swappedItem.persistentID)])
                let insertItem = mutableQueue.items.count == 0 ? nil : mutableQueue.items[to]
                mutableQueue.insert(descripter, after: insertItem)
            }, completionHandler: { [unowned self] queue, error in
                defer {
                    self.dispatchSemaphore.signal()
                }
                guard (error == nil) else {
                    print("Re-Insert Failed")
                    return
                } // TODO: 挿入ができなかった時の処理
                self.items = queue.items
                if let completion = completion { completion() }
                NotificationCenter.default.post(name: .DJYusakuPlayerQueueDidUpdate, object: nil)
            })
        })
  

    }
    
    func add(with song : Song, completion: (() -> (Void))? = nil) {
        if !isQueueCreated { // キューが初期化されていないとき
            self.create(with: song, completion: completion)
        } else {            // 既にキューが作られているとき
            self.insert(after: items.count - 1, with: song, completion: completion)
        }
    }
    
    func count() -> Int {
        return items.count
    }
    
    func get(at index: Int) -> MPMediaItem? {
        guard index >= 0 && self.count() > index else { return nil }
        return items[index]
    }
    
}
