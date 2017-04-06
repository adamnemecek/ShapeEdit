//
//  Extensions.swift
//  ShapeEdit
//
//  Created by Adam Nemecek on 4/5/17.
//  Copyright © 2017 Apple Inc. All rights reserved.
//

import SceneKit

extension SCNVector3  {
    public func encode(with aCoder: NSCoder) {
        aCoder.encode(x, forKey: "x")
        aCoder.encode(y, forKey: "y")
        aCoder.encode(z, forKey: "z")
        
    }
    
    public init?(coder aDecoder: NSCoder) {
        x = aDecoder.decodeFloat(forKey: "x")
        y = aDecoder.decodeFloat(forKey: "y")
        z = aDecoder.decodeFloat(forKey: "z")
    }
}

extension SCNVector4  {
    public func encode(with aCoder: NSCoder) {
        aCoder.encode(x, forKey: "rx")
        aCoder.encode(y, forKey: "ry")
        aCoder.encode(z, forKey: "rz")
        aCoder.encode(w, forKey: "rw")
        
    }
    
    public init?(coder aDecoder: NSCoder) {
        x = aDecoder.decodeFloat(forKey: "rx")
        y = aDecoder.decodeFloat(forKey: "ry")
        z = aDecoder.decodeFloat(forKey: "rz")
        w = aDecoder.decodeFloat(forKey: "rw")
    }
}
