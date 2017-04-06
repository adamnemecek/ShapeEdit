/*
    Copyright (C) 2016 Apple Inc. All Rights Reserved.
    See LICENSE.txt for this sample’s licensing information
    
    Abstract:
    `ThumbnailCache` manages loading thumbnails on background queues and keeping track of which thumbnails are up to date. It also stores thumbnails in a cache for quick access at a later time.
*/

import UIKit

/**
    This delegate protocol is implemented so we can receive a callback when the
    thumbnail is loaded.
*/
protocol ThumbnailCacheDelegate: class {
    func thumbnailCache(_ thumbnailCache: ThumbnailCache, didLoadThumbnailsForURLs: Set<URL>)
}
//
//extension NSCache {
//    subscript(key: KeyType) -> ObjectType? {
//        get {
//            return object(forKey: key)
//        }
//        set {
//            setObject(key, forKey: newValue)
//        }
//    }
//}

/**
    The thumbnail cache class handles loading thumbnails, scaling the thumbnails
    to the propper size for our UI and informing its delegate once they're loaded.
*/

extension RangeReplaceableCollection where Iterator.Element : Equatable {
    @discardableResult
    mutating func remove(_ element: Iterator.Element) -> Index? {
        return index(of: element).map {
            self.remove(at: $0)
            return $0
        }
    }
}



extension NSCache {
    convenience init(name: String, count: Int) {
        self.init()
        self.name = name
        self.countLimit = count
    }
}

extension OperationQueue {
    convenience init(name: String, count: Int = ThumbnailCache.concurrentThumbnailOperations) {
        self.init()
        self.name = name
        self.maxConcurrentOperationCount = count
    }
}


class ThumbnailCache {
    // MARK: - Properties

    fileprivate let cache = NSCache<NSNumber, UIImage>(name: "com.example.apple-samplecode.ShapeEdit.thumbnailcache.cache", count: 64)

    fileprivate let workerQueue = OperationQueue(name: "com.example.apple-samplecode.ShapeEdit.thumbnailcache.workerQueue")
    
    let thumbnailSize: CGSize
    
    fileprivate var URLsNeedingReload = Set<URL>()
    
    fileprivate var pendingThumbnails = [Int: Set<URL>]()
    
    fileprivate var cleanThumbnailDocumentIDs = Set<Int>()
    
    fileprivate var unscheduledDocumentIDs = [Int]()
    
    fileprivate var runningDocumentIDCount = 0
    
    fileprivate var scheduleSource: DispatchSource
    
    fileprivate var flushSource: DispatchSource
    
    weak var delegate: ThumbnailCacheDelegate?
    
    static let concurrentThumbnailOperations = 4

    // MARK: - Initialization

    init (thumbnailSize:CGSize) {
        self.thumbnailSize = thumbnailSize
        
        scheduleSource = DispatchSource.makeUserDataOrSource(queue: .main) /*Migrator FIXME: Use DispatchSourceUserDataOr to avoid the cast*/ as! DispatchSource
        
        flushSource = DispatchSource.makeUserDataOrSource(queue: .main) /*Migrator FIXME: Use DispatchSourceUserDataOr to avoid the cast*/ as! DispatchSource
        
        // Set up our scheduler which will manage an array of pending thumbnails
        scheduleSource.setEventHandler { [weak self] in
            guard let strongSelf = self else { return }
            
            strongSelf.scheduleThumbnailLoading()
        }
        
        scheduleSource.resume()
        
        // Set up our source which will push a batch of thumbnail updates at once.
        flushSource.setEventHandler { [weak self] in
            guard let strongSelf = self else { return }
            
            strongSelf.delegate?.thumbnailCache(strongSelf, didLoadThumbnailsForURLs: strongSelf.URLsNeedingReload)
            strongSelf.URLsNeedingReload.removeAll()
        }
        
        flushSource.resume()
    }

    // MARK: - Cache Management
    
    func markThumbnailCacheDirty() {
        // We've been asked to reload the UI and need to reload all items in the cache.
        cleanThumbnailDocumentIDs.removeAll()
    }

    func markThumbnailDirtyForURL(_ url: Foundation.URL) {
        /*
            Mark the item dirty so that we know the next time we are asked for the
            thumbnail that we need to reload it.
        */
        if let documentIdentifier = documentIdentifierForURL(url) {
            cleanThumbnailDocumentIDs.remove(documentIdentifier)
        }
    }

    func removeThumbnailForURL(_ url: Foundation.URL) {
        /*
            Remove the item entirely from the cache because the item existing in the cache no
            longer makes sense for that URL.
        */
        if let documentIdentifier = documentIdentifierForURL(url) {
            cache.removeObject(forKey: NSNumber(value: documentIdentifier))
            
            cleanThumbnailDocumentIDs.remove(documentIdentifier)
        }
    }
    
    func cancelThumbnailLoadForURL(_ url: Foundation.URL) {
        if let documentIdentifier = documentIdentifierForURL(url) {
            if let index = unscheduledDocumentIDs.index(of: documentIdentifier) {
                unscheduledDocumentIDs.remove(at: index)
                
                pendingThumbnails[documentIdentifier] = nil
            }
        }
    }
    

    // MARK: - Thumbnail Loading
    
    fileprivate func documentIdentifierForURL(_ url: Foundation.URL) -> Int? {
        // Look up the document identifier on the URL which uniquely identifies a document.
        do {
            var documentIdentifier: AnyObject?
            try (url as NSURL).getPromisedItemResourceValue(&documentIdentifier, forKey: URLResourceKey.documentIdentifierKey)
            
            return documentIdentifier as? Int
        }
        catch {
            return nil
        }
    }
    
    fileprivate func scheduleThumbnailLoading() {
        // While we have work left to schedule, schedule a thumbnail fetch in the background
        while self.runningDocumentIDCount < ThumbnailCache.concurrentThumbnailOperations {
            guard let nextDocumentID = self.unscheduledDocumentIDs.first else { break }
            
            self.unscheduledDocumentIDs.remove(nextDocumentID)
            
            self.runningDocumentIDCount += 1
            
            let thumbnailURL = self.pendingThumbnails[nextDocumentID]!.first!
            
            let alreadyCached = self.cache.object(forKey: NSNumber(value: nextDocumentID)) != nil
            
            self.loadThumbnailInBackgroundForURL(thumbnailURL, documentIdentifier: nextDocumentID, alreadyCached: alreadyCached)
        }
    }
    
    fileprivate func loadThumbnailInBackgroundForURL(_ url: Foundation.URL, documentIdentifier: Int, alreadyCached: Bool) {
        self.workerQueue.addOperation {
            if let thumbnail = self.loadThumbnailFromDiskForURL(url) {
                // Scale the image to correct size.
                UIGraphicsBeginImageContextWithOptions(self.thumbnailSize, false, UIScreen.main.scale)
                
                let thumbnailRect = CGRect(x: 0, y: 0, width: self.thumbnailSize.width, height: self.thumbnailSize.height)
                
                thumbnail.draw(in: thumbnailRect)
                
                let scaledThumbnail = UIGraphicsGetImageFromCurrentImageContext()
                
                UIGraphicsEndImageContext()
                
                /*
                    Thumbnail loading succeeded. Save the thumbnail and call the
                    reload blocks to reload the UI.
                */
                self.cache.setObject(scaledThumbnail!, forKey: NSNumber(value: documentIdentifier))
                
                OperationQueue.main.addOperation {
                    self.cleanThumbnailDocumentIDs.insert(documentIdentifier)
                    
                    // Fetch all URLs for this `documentIdentifier`, not just the provided `URL` parameter.
                    let URLsForDocumentIdentifier = self.pendingThumbnails[documentIdentifier]!
                    
                    // Join the URLs for this identifier to any other URLs due for updating.
                    self.URLsNeedingReload.formUnion(URLsForDocumentIdentifier)
                    
                    self.pendingThumbnails[documentIdentifier] = nil
                    
                    // Trigger the event handler for the `flushSource` updating a batch of thumbnails.
                    self.flushSource.add(data: 1)

                    self.runningDocumentIDCount -= 1
                    
                    // Trigger the event handler for the `scheduleSource` scheduling thumbnail loading.
                    self.scheduleSource.add(data: 1)
                }
            }
            else {
                // Thumbnail loading failed. Just use the most recent cached thumbail.
                if !alreadyCached {
                    let image = UIImage(named: "MissingThumbnail.png")!
                    self.cache.setObject(image, forKey: NSNumber(value: documentIdentifier))
                }
                
                OperationQueue.main.addOperation {
                    self.cleanThumbnailDocumentIDs.insert(documentIdentifier)
                    
                    self.pendingThumbnails[documentIdentifier] = nil

                    self.runningDocumentIDCount -= 1
                    
                    // Trigger the event handler for the `scheduleSource` scheduling thumbnail loading.
                    self.scheduleSource.add(data: 1)
                }
            }
        }
    }
    
    func loadThumbnailForURL(_ url: Foundation.URL) -> UIImage {
        /*
            We load the existing thumbnail (or a placeholder image if none has been
            loaded yet) and check if it is clean or not. If it isn't clean, we 
            load the thumbnail on a background queue to avoid blocking the main
            thread which could hamper scroll performance. Regardless of whether or
            not the thumbnail is clean, return the most up-to-date version of the
            thumbnail so we are sure to display something relatively up-to-date in 
            the UI.
        */
        
        /*
            We cache everything in our thumbnail cache by document identifier which
            is tracked properly accross renames.
        */
        guard let documentIdentifier = documentIdentifierForURL(url) else {
            print("Failed to load docID and will display placeholder image for \(url)")
            
            return UIImage(named: "MissingThumbnail.png")!
        }
        
        let existingImage = cache.object(forKey: NSNumber(value: documentIdentifier))
        
        if let existingImage = existingImage, cleanThumbnailDocumentIDs.contains(documentIdentifier) {
            // Everything fully up-to-date - return the cached image.
            return existingImage
        }

        // Use a placeholder image if one hasn't been loaded yet.
        let loadedThumbnail = existingImage ?? UIImage(named: "MissingThumbnail.png")!

        // If we are already loading that thumbnail, add our url to the reload list.
        if let URLs = pendingThumbnails[documentIdentifier] {
            pendingThumbnails[documentIdentifier] = URLs.union([url])

            return loadedThumbnail
        }
        
        // Schedule the thumbnail to be loaded on a background queue.
        pendingThumbnails[documentIdentifier] = [url]
        
        unscheduledDocumentIDs += [documentIdentifier]
        
        // Trigger the event handler for the `scheduleSource` scheduling thumbnail loading.
        scheduleSource.add(data: 1)
        
        // Return the most up-to-date image we have currently.
        return loadedThumbnail
    }
    
    fileprivate func loadThumbnailFromDiskForURL(_ url: Foundation.URL) -> UIImage? {
        do {
            /*
                Load the thumbnail from disk.  Use getPromisedItemResourceValue because
                the document might not have been downloaded yet.
            */
            var thumbnailDictionary: AnyObject?
            try (url as NSURL).getPromisedItemResourceValue(&thumbnailDictionary, forKey: URLResourceKey.thumbnailDictionaryKey)

            /*
                We don't want to hang onto this in the URL cache because the URL 
                is long running and we maintain a separate cache for the thumbnails.
            */
            (url as NSURL).removeCachedResourceValue(forKey: URLResourceKey.thumbnailDictionaryKey)
            
            guard let dictionary = thumbnailDictionary as? [String: UIImage],
                
                let image = dictionary[URLThumbnailDictionaryItem.NSThumbnail1024x1024SizeKey.rawValue] else {
                    throw ShapeEditError.thumbnailLoadFailed
            }
            
            return image
        }
        catch {
            return nil
        }
    }
}
