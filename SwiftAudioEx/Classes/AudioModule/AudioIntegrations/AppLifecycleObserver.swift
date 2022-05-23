//
//  AppLifecycleObserver.swift
//  KeepTalkingFM
//
//  Created by Marina Gornostaeva on 11/05/2022.
//

import UIKit

protocol AppLifecycleObserverDelegate: AnyObject {
    func applicationDidEnterBackground(_ observer: AppLifecycleObserver)
    func applicationWillEnterForeground(_ observer: AppLifecycleObserver)
    func applicationDidBecomeActive(_ observer: AppLifecycleObserver)
    func applicationWillResignActive(_ observer: AppLifecycleObserver)
    func applicationWillTerminate(_ observer: AppLifecycleObserver)
}

final class AppLifecycleObserver {
    weak var delegate: AppLifecycleObserverDelegate?
    
    var applicationState: UIApplication.State {
        return UIApplication.shared.applicationState
    }
    
    private var backgroundTasks: [BackgroundTask] = []
    
    init() {
        NotificationCenter.default.addObserver(self, selector: #selector(didEnterBackground(note:)), name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(willEnterForeground(note:)), name: UIApplication.willEnterForegroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(didBecomeActive(note:)), name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(willResignActive(note:)), name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(willTerminate(note:)), name: UIApplication.willTerminateNotification, object: nil)
    }
    
    func startNewBackgroundTask() {
        backgroundTasks.append(BackgroundTask())
    }
    
    func finishAllBackgroundTasks() {
        backgroundTasks = []
    }
    
    @objc private func didEnterBackground(note: Notification) {
        delegate?.applicationDidEnterBackground(self)
    }
    
    @objc private func willEnterForeground(note: Notification) {
        delegate?.applicationWillEnterForeground(self)
    }
    
    @objc private func didBecomeActive(note: Notification) {
        delegate?.applicationDidBecomeActive(self)
    }
    
    @objc private func willResignActive(note: Notification) {
        delegate?.applicationWillResignActive(self)
    }
    
    @objc private func willTerminate(note: Notification) {
        delegate?.applicationWillTerminate(self)
    }
}

extension AppLifecycleObserver {
    
    private class BackgroundTask {
        
        private var identifier: UIBackgroundTaskIdentifier = .invalid
        
        init() {
            identifier = UIApplication.shared.beginBackgroundTask(withName: "audio_task_\(UUID().uuidString)") { [weak self] in
                self?.end()
            }
            print("BackgroundTask START \(identifier)")
        }
        
        deinit {
            end()
        }
        
        func end() {
            print("BackgroundTask ENDING \(identifier)")
            UIApplication.shared.endBackgroundTask(identifier)
        }
    }
}
