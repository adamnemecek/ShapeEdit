/*
    Copyright (C) 2016 Apple Inc. All Rights Reserved.
    See LICENSE.txt for this sample’s licensing information
    
    Abstract:
    This is the Browser Query which manages results form an `NSMetadataQuery` to compute which documents to show in the Browser UI / animations to display when cells move.
*/

import UIKit

/**
    The delegate protocol implemented by the object that receives our results. We
    pass the updated list of results as well as a set of animations.
*/
protocol DocumentBrowserQueryDelegate: class {
    func documentBrowserQueryResultsDidChangeWithResults(_ results: [NSMetadataItem], animations: [DocumentBrowserAnimation])
}

extension NSOrderedSet {
    @inline(__always)
    func _index(of object: Any) -> Int? {
        let idx = index(of: object)
        if idx == NSNotFound {
            return nil
        }
        return idx
    }
}

extension Notification {
    subscript (metadata forKey: String) -> NSOrderedSet {
        let meta = userInfo?[forKey] as? [NSMetadataItem] ?? []
        return NSOrderedSet(array: meta.sorted())
    }
}

extension NSMetadataQuery {
    func resultSet() -> NSOrderedSet {
        /*
         Create an ordered set of model objects from the query's current
         result set.
         */
        
        disableUpdates()
        let res = results as! [NSMetadataItem]
        enableUpdates()
        return NSOrderedSet(array: res.sorted())
    }
}

/**
    The DocumentBrowserQuery wraps an `NSMetadataQuery` to insulate us from the
    queueing and animation concerns. It runs the query and computes animations
    from the results set.
*/
class DocumentBrowserQuery: NSMetadataQuery {
    // MARK: - Properties

    fileprivate var previous: NSOrderedSet?
    
    fileprivate let workerQueue = OperationQueue(name: .browser)

    var _delegate: DocumentBrowserQueryDelegate? {
        didSet {
            /*
                If we already have results, we send them to the delegate as an
                initial update.
            */
            workerQueue.addOperation {
                self.previous.map {
                    self.update(with: $0)
                }
            }
        }
    }

    // MARK: - Initialization

    override init() {
        super.init()
        
        // Filter only our document type.
        let filePattern = String(format: "*.%@", DocumentBrowserController.documentExtension)
        self.predicate = NSPredicate(format: "%K LIKE %@", NSMetadataItemFSNameKey, filePattern)
        
        /*
            Ask for both in-container documents and external documents so that
            the user gets to interact with all the documents she or he has ever
            opened in the application, without having to pull the document picker
            again and again.
        */
        self.searchScopes = [
            NSMetadataQueryUbiquitousDocumentsScope,
            NSMetadataQueryAccessibleUbiquitousExternalDocumentsScope
        ]

        /*
            We supply our own serializing queue to the `NSMetadataQuery` so that we
            can perform our own background work in sync with item discovery.
            Note that the operationQueue of the `NSMetadataQuery` must be serial.
        */
        self.operationQueue = workerQueue

        NotificationCenter.default.addObserver(self, selector: #selector(finishGathering), name: .NSMetadataQueryDidFinishGathering, object: nil)

        NotificationCenter.default.addObserver(self, selector: #selector(queryUpdated), name: .NSMetadataQueryDidUpdate, object: nil)

        start()
    }
    
    // MARK: - Notifications

    @objc func queryUpdated(_ notification: Notification) {
        update(with: resultSet(),
               removed: notification[metadata: NSMetadataQueryUpdateRemovedItemsKey],
               added: notification[metadata: NSMetadataQueryUpdateAddedItemsKey],
               changed: notification[metadata: NSMetadataQueryUpdateChangedItemsKey])
    }

    @objc func finishGathering(_ notification: Notification) {
        update(with: resultSet())
    }

    fileprivate func computeAnimations(for newResults: NSOrderedSet, old: NSOrderedSet, removed: NSOrderedSet, added: NSOrderedSet, changed: NSOrderedSet) -> [DocumentBrowserAnimation] {
        /*
           From two sets of result objects, create an array of animations that
           should be run to morph old into new results.
        */

        let oldResultAnimations: [DocumentBrowserAnimation] = removed.flatMap {
            old._index(of: $0).map { .delete(index: $0) }
        }
        
        let newResultAnimations: [DocumentBrowserAnimation] = added.flatMap {
            newResults._index(of: $0).map { .add(index: $0) }
        }

        let movedResultAnimations: [DocumentBrowserAnimation] = changed.flatMap {
            if let newIndex = newResults._index(of: $0),
                let oldIndex = old._index(of: $0), oldIndex == newIndex {
                return .move(fromIndex: oldIndex, toIndex: newIndex)
            }
            return nil
        }

        // Find all the changed result animations.
        let changedResultAnimations: [DocumentBrowserAnimation] = changed.flatMap {
            newResults._index(of: $0).map { .update(index: $0) }
        }
        
        return oldResultAnimations + changedResultAnimations + newResultAnimations + movedResultAnimations
    }

    fileprivate func update(with results: NSOrderedSet = [], removed: NSOrderedSet = [], added: NSOrderedSet = [], changed: NSOrderedSet = []) {
        /*
            From a set of new result objects, we compute the necessary animations
            if applicable, then call out to our delegate.
        */

        /*
            We use the `NSOrderedSet` as a fast lookup for computing the animations,
            but use a simple array otherwise for convenience.
        */
        let queryAnimations: [DocumentBrowserAnimation] = previous.map {
            self.computeAnimations(for: results, old: $0, removed: removed, added: added, changed: changed)
        } ?? [.reload]

        // After computing updates, we hang on to the current results for the next round.
        previous = results

        let queryResults = results.array as! [NSMetadataItem]
        OperationQueue.main.addOperation {
            self._delegate?.documentBrowserQueryResultsDidChangeWithResults(queryResults, animations: queryAnimations)
        }
    }
}
