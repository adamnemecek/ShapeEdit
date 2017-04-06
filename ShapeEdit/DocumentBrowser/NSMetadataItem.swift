/*
    Copyright (C) 2016 Apple Inc. All Rights Reserved.
    See LICENSE.txt for this sample’s licensing information
    
    Abstract:
    This is the model object which represents one document on disk.
*/

import UIKit

extension NSMetadataItem : Comparable, ModelObject {
    
    public var displayName: String {
        return value(forAttribute: NSMetadataItemDisplayNameKey) as! String
    }

    public static func ==(lhs: NSMetadataItem, rhs: NSMetadataItem) -> Bool {
        return lhs.displayName == rhs.displayName
    }
    
    public static func <(lhs: NSMetadataItem, rhs: NSMetadataItem) -> Bool {
        return lhs.displayName < rhs.displayName
    }
    
    public var subtitle : String {
        if let isExternal = value(forAttribute: NSMetadataUbiquitousItemIsExternalDocumentKey) as? Bool, isExternal,
            let containerName = value(forAttribute: NSMetadataUbiquitousItemContainerDisplayNameKey) as? String {
            return "in \(containerName)"
        }
        return ""
    }
    
    public var url: URL {
        return value(forAttribute: NSMetadataItemURLKey) as! URL
    }
}
