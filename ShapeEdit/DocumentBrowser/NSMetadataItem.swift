/*
 Copyright (C) 2016 Apple Inc. All Rights Reserved.
 See LICENSE.txt for this sample’s licensing information
 
 Abstract:
 This is the model object which represents one document on disk.
 */

import UIKit

extension NSMetadataItem : Comparable, ModelObject {
    private enum Key : String {
        case isExternalDocumentKey, containerDisplayNameKey, urlKey, displayKeyName
        
        var rawValue: String {
            switch self {
            case .isExternalDocumentKey: return NSMetadataUbiquitousItemIsExternalDocumentKey
            case .containerDisplayNameKey: return NSMetadataUbiquitousItemContainerDisplayNameKey
            case .urlKey: return NSMetadataItemURLKey
            case .displayKeyName: return NSMetadataItemDisplayNameKey
            }
        }
    }
    
    private subscript(key: Key) -> Any? {
        return value(forAttribute: key.rawValue)
    }
    
    public var displayName: String {
        return self[.displayKeyName] as! String
    }
    
    public static func ==(lhs: NSMetadataItem, rhs: NSMetadataItem) -> Bool {
        return lhs.displayName == rhs.displayName
    }
    
    public static func <(lhs: NSMetadataItem, rhs: NSMetadataItem) -> Bool {
        return lhs.displayName < rhs.displayName
    }
    
    public var subtitle : String {
        if let isExternal = self[.isExternalDocumentKey] as? Bool, isExternal,
            let containerName = self[.containerDisplayNameKey] as? String {
            return "in \(containerName)"
        }
        return ""
    }
    
    public var url: URL {
        return self[.urlKey] as! URL
    }
}
