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

class OrderedSet<Element: AnyObject> : NSOrderedSet {
    
}

/**
    The DocumentBrowserQuery wraps an `NSMetadataQuery` to insulate us from the
    queueing and animation concerns. It runs the query and computes animations
    from the results set.
*/
class DocumentBrowserQuery: NSObject {
    // MARK: - Properties

    fileprivate var metadataQuery: NSMetadataQuery
    
    fileprivate var previousQueryObjects: NSOrderedSet?
    
    fileprivate let workerQueue: OperationQueue = {
        let workerQueue = OperationQueue()
        
        workerQueue.name = "com.example.apple-samplecode.ShapeEdit.browserdatasource.workerQueue"

        workerQueue.maxConcurrentOperationCount = 1
        
        return workerQueue
    }()

    var delegate: DocumentBrowserQueryDelegate? {
        didSet {
            /*
                If we already have results, we send them to the delegate as an
                initial update.
            */
            workerQueue.addOperation {
                self.previousQueryObjects.map {
                    self.updateWithResults($0)
                }
            }
        }
    }

    // MARK: - Initialization

    override init() {
        metadataQuery = NSMetadataQuery()
        
        // Filter only our document type.
        let filePattern = String(format: "*.%@", DocumentBrowserController.documentExtension)
        metadataQuery.predicate = NSPredicate(format: "%K LIKE %@", NSMetadataItemFSNameKey, filePattern)
        
        /*
            Ask for both in-container documents and external documents so that
            the user gets to interact with all the documents she or he has ever
            opened in the application, without having to pull the document picker
            again and again.
        */
        metadataQuery.searchScopes = [
            NSMetadataQueryUbiquitousDocumentsScope,
            NSMetadataQueryAccessibleUbiquitousExternalDocumentsScope
        ]

        /*
            We supply our own serializing queue to the `NSMetadataQuery` so that we
            can perform our own background work in sync with item discovery.
            Note that the operationQueue of the `NSMetadataQuery` must be serial.
        */
        metadataQuery.operationQueue = workerQueue

        super.init()

        NotificationCenter.default.addObserver(self, selector: #selector(finishGathering), name: .NSMetadataQueryDidFinishGathering, object: metadataQuery)

        NotificationCenter.default.addObserver(self, selector: #selector(queryUpdated), name: .NSMetadataQueryDidUpdate, object: metadataQuery)

        metadataQuery.start()
    }
    
    // MARK: - Notifications

    @objc func queryUpdated(_ notification: Notification) {
        let changedMetadataItems = notification.userInfo?[NSMetadataQueryUpdateChangedItemsKey] as? [NSMetadataItem]
        
        let removedMetadataItems = notification.userInfo?[NSMetadataQueryUpdateRemovedItemsKey] as? [NSMetadataItem]
        
        let addedMetadataItems = notification.userInfo?[NSMetadataQueryUpdateAddedItemsKey] as? [NSMetadataItem]
        
        let changedResults = buildModelObjectSet(changedMetadataItems ?? [])
        let removedResults = buildModelObjectSet(removedMetadataItems ?? [])
        let addedResults = buildModelObjectSet(addedMetadataItems ?? [])
        
        let newResults = buildQueryResultSet()

        updateWithResults(newResults, removedResults: removedResults, addedResults: addedResults, changedResults: changedResults)
    }

    @objc func finishGathering(_ notification: Notification) {
        metadataQuery.disableUpdates()
        
        let metadataQueryResults = metadataQuery.results as! [NSMetadataItem]
        
        let results = buildModelObjectSet(metadataQueryResults)
                
        metadataQuery.enableUpdates()

        updateWithResults(results)
    }

    // MARK: - Result handling/animations

    fileprivate func buildModelObjectSet(_ objects: [NSMetadataItem]) -> NSOrderedSet {
        // Create an ordered set of model objects.
        return NSOrderedSet(array: objects.sorted())
    }
    
    fileprivate func buildQueryResultSet() -> NSOrderedSet {
        /*
           Create an ordered set of model objects from the query's current
           result set.
        */

        metadataQuery.disableUpdates()

        let metadataQueryResults = metadataQuery.results as! [NSMetadataItem]

        let results = buildModelObjectSet(metadataQueryResults)

        metadataQuery.enableUpdates()

        return results
    }

    fileprivate func computeAnimationsForNewResults(_ newResults: NSOrderedSet, oldResults: NSOrderedSet, removedResults: NSOrderedSet, addedResults: NSOrderedSet, changedResults: NSOrderedSet) -> [DocumentBrowserAnimation] {
        /*
           From two sets of result objects, create an array of animations that
           should be run to morph old into new results.
        */
        
        let oldResultAnimations: [DocumentBrowserAnimation] = removedResults.array.flatMap { removedResult in
            return oldResults._index(of: removedResult).map { .delete(index: $0) }
        }
        
        let newResultAnimations: [DocumentBrowserAnimation] = addedResults.array.flatMap { addedResult in
            let newIndex = newResults.index(of: addedResult)
            
            guard newIndex != NSNotFound else { return nil }
            
            return .add(index: newIndex)
        }

        let movedResultAnimations: [DocumentBrowserAnimation] = changedResults.array.flatMap { movedResult in
            if let newIndex = newResults._index(of: movedResult),
                let oldIndex = oldResults._index(of: movedResult), oldIndex == newIndex {
                return .move(fromIndex: oldIndex, toIndex: newIndex)
            }
            return nil
        }

        // Find all the changed result animations.
        let changedResultAnimations: [DocumentBrowserAnimation] = changedResults.array.flatMap { changedResult in
            return newResults._index(of: changedResult).map { .update(index: $0) }
        }
        
        return oldResultAnimations + changedResultAnimations + newResultAnimations + movedResultAnimations
    }

    fileprivate func updateWithResults(_ results: NSOrderedSet = [], removedResults: NSOrderedSet = [], addedResults: NSOrderedSet = [], changedResults: NSOrderedSet = []) {
        /*
            From a set of new result objects, we compute the necessary animations
            if applicable, then call out to our delegate.
        */

        /*
            We use the `NSOrderedSet` as a fast lookup for computing the animations,
            but use a simple array otherwise for convenience.
        */
        let queryResults = results.array as! [NSMetadataItem]

        let queryAnimations: [DocumentBrowserAnimation]

        if let oldResults = previousQueryObjects {
            queryAnimations = computeAnimationsForNewResults(results, oldResults: oldResults, removedResults: removedResults, addedResults: addedResults, changedResults: changedResults)
        }
        else {
            queryAnimations = [.reload]
        }

        // After computing updates, we hang on to the current results for the next round.
        previousQueryObjects = results

        OperationQueue.main.addOperation {
            self.delegate?.documentBrowserQueryResultsDidChangeWithResults(queryResults, animations: queryAnimations)
        }
    }
}
