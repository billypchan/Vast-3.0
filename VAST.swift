//
//  VAST.swift
//  mobeat
//
//  Created by ALI KIRAN on 20/05/16.
//  Copyright © 2016 ALI KIRAN. All rights reserved.
//


import Foundation
import AEXML
import Signals

protocol VASTResource {
    
}

extension String {
    func asXMLBool() -> Bool {
        return self == "true" || self == "1" ? true : false
    }
    
    func asXMLInt() -> Int {
        return Int(self) ?? 0
    }
}

func dlog(_ msg: String) {
    print(msg)
}

open class Vast {
    private(set) var url: URL
    private(set) var version: Version?
    private(set) var adObjects: [AdObject] = []
    
    var errorSignal = Signal<String>()
    
    public init(url: URL, handler: (([AdObject]?) -> ())?) {
        self.url = url
        
        self.errorSignal.subscribe(on: self) { (error) in
            dlog("vast error: \(error)")
        }
        
        if (url.absoluteString.contains("file:///")) {
            guard let data = NSData(contentsOf: url as URL) else {
                return
            }
            
            DispatchQueue.global(qos: .userInitiated).async {
                self.parseVastData(data: data as Data)
                DispatchQueue.main.async {
                    if let handler = handler {
                        handler(self.adObjects)
                    }
                }
            }
            
        } else {
            
            let request = NSMutableURLRequest(url: url as URL)
            let task = URLSession.shared.dataTask(
                with: request as URLRequest, completionHandler: {
                    data, response, error in
                    guard let data = data else {
                        if let error = error {
                            self.errorSignal.fire(error.localizedDescription)
                        } else {
                            self.errorSignal.fire("Unable to load xml from server")
                        }
                        return
                    }
                    
                    DispatchQueue.global(qos: .userInitiated).async {
                        self.parseVastData(data: data as Data)
                        DispatchQueue.main.async {
                            if let handler = handler {
                                handler(self.adObjects)
                            }
                        }
                    }
                    
            })
            
            task.resume()
            
        }
    }
    
    func parseVastData(data: Data) {
        do {
            let xmlDoc = try AEXMLDocument(xml: data)
            guard xmlDoc.root.name == "VAST" else {
                errorSignal.fire("invalid VAST format")
                return
            }
            
            if let v = xmlDoc.root.attributes["version"] {
                self.version = Version(rawValue: v)
                if self.version == nil {
                    errorSignal.fire("unsupported version \(v)")
                }
            }
            
            guard let adsXML = xmlDoc.root["Ad"].all else {
                return
            }
            
            for adXML in adsXML {
                let ad = AdObject()
                ad.id = adXML.attributes["id"]
                ad.sequence = adXML.attributes["sequence"]
                
                for adChild in adXML.children {
                    switch adChild.name {
                    case "InLine":
                        
                        let system: AdObject.AdSystem? = AdObject.AdSystem(value: adChild["AdSystem"].value, version: adChild["AdSystem"].attributes["version"])
                        
                        let pricing: AdObject.Pricing? = AdObject.Pricing(value: adChild["Pricing"].value, model: adChild["Pricing"].attributes["model"], currency: adChild["Pricing"].attributes["currency"])
                        
                        ad.inline = AdObject.Inline(system: system, title: adChild["AdTitle"].value, description: adChild["Description"].value, advertiser: adChild["Advertiser"].value, pricing: pricing, survey: adChild["Survey"].uri(), error: adChild["Error"].uri(), extensions: adChild["Extensions"]["Extension"])
                        ad.inline?.creatives = adChild.Creatives()
                        ad.inline?.impressions = adChild.Impressions()
                        adObjects.append(ad)
                        ad.isInline = true
                        
                        break
                    case "Wrapper":
                        let system: AdObject.AdSystem? = AdObject.AdSystem(value: adChild["AdSystem"].value, version: adChild["AdSystem"].attributes["version"])
                        ad.wrapper = AdObject.Wrapper(system: system, VASTAdTagURI: adChild["VASTAdTagURI"].uri(), error: adChild["Error"].uri(), extensions: adChild["Extensions"]["Extension"])
                        ad.wrapper?.creatives = adChild.Creatives()
                        ad.wrapper?.impressions = adChild.Impressions()
                        adObjects.append(ad)
                        ad.isInline = false
                        break
                    default:
                        break
                    }
                }
                
            }
            
        } catch {
            errorSignal.fire("\(error)")
            
        }
        
    }
    
    enum Version: String {
        case v3_0 = "3.0", v2_1 = "2.1", v2_0 = "2.0"
    }
    
    public class AdObject {
        public var id: String?
        // Identifies the sequence of multiple Ads and defines an Ad Pod.
        var sequence: String?
        // Second-level element surrounding wrapper ad pointing to Secondary ad server.
        var wrapper: Wrapper?
        // Second-level element surrounding complete ad data for a single ad
        public var inline: Inline?
        var isInline: Bool = false
        
        // Indicates source ad server
        struct AdSystem {
            init?(value: String?, version: String?) {
                guard let value = value else {
                    return nil
                }
                self.value = value
                self.version = version
                
            }
            
            // Internal version used by ad system
            var version: String?
            var value: String
        }
        
        struct Pricing {
            init?(value: String?, model: String?, currency: String?) {
                guard value != nil else {
                    return nil
                }
                self.value = value
                self.model = model
                self.currency = currency
            }
            var value: String!
            // model: identifies the pricing model as one of “CPM”, “CPC”, “CPE”, or “CPV”.
            var model: String!
            // currency: the 3-letter ISO-4217 currency symbol that identifies the currency of the value provided (i.e. USD, GBP, etc.…)
            var currency: String!
        }
        
        public class URIIdentifier {
            init?(uri: String?, id: String?) {
                guard let uri = uri else {
                    return nil
                }
                
                self.uri = uri
                self.id = id
            }
            var id: String?
            // The anyURI datatype represents a Uniform Resource Identifier Reference (URI).
            public var uri: String!
        }
        
        class TrackURIIdentifier: URIIdentifier {
            // The name of the event to track. For nonlinear ads these events should be recorded on the video within the ad.
            var event: String!
            // The time during the video at which this url should be pinged. Must be present for progress event.
            var offset: String?
            
            init?(event: String?, offset: String?, uri: String?, id: String?) {
                super.init(uri: uri, id: id)
                
                guard let uri = uri, let event = event else {
                    return nil
                }
                
                self.offset = offset
                self.event = event
                self.uri = uri
                self.id = id
            }
            // Mime type of static resource (if static resource)
            var creativeType: String!
        }
        
        struct Parameter {
            var value: String!
            var xmlEncoded: Bool?
            
            init?(value: String?, xmlEncoded: String?) {
                
                guard let value = value else {
                    return nil
                }
                
                self.xmlEncoded = xmlEncoded?.asXMLBool()
                self.value = value
            }
        }
        
        struct Wrapper {
            init?(system: AdSystem?, VASTAdTagURI: URIIdentifier?, error: URIIdentifier?, extensions: AEXMLElement?) {
                guard let system = system, let VASTAdTagURI = VASTAdTagURI else {
                    return nil
                }
                
                self.system = system
                self.VASTAdTagURI = VASTAdTagURI
                self.error = error
                self.extensions = extensions
            }
            
            var system: AdSystem!
            var VASTAdTagURI: URIIdentifier!
            var error: URIIdentifier?
            var extensions: AEXMLElement?
            
            var impressions: [URIIdentifier] = []
            // Contains all creative elements within an InLine or Wrapper Ad
            var creatives: [Creative] = []
            
        }
        
        public struct Inline {
            init?(system: AdSystem?, title: String?, description: String?, advertiser: String?, pricing: AdObject.Pricing?, survey: URIIdentifier?, error: URIIdentifier?, extensions: AEXMLElement?) {
                guard let system = system, let title = title else {
                    return nil
                }
                
                self.system = system
                self.title = title
                self.description = description
                self.advertiser = advertiser
                self.pricing = pricing
                self.survey = survey
                self.error = error
                self.extensions = extensions
            }
            
            // Indicates source ad server
            var system: AdSystem!
            // Common name of ad
            var title: String!
            // Longer description of ad
            var description: String?
            // Common name of advertiser
            var advertiser: String?
            // The price of the ad.
            var pricing: AdObject.Pricing?
            // URL of request to survey vendor
            var survey: URIIdentifier?
            // URL to request if ad does not play due to error
            var error: URIIdentifier?
            var extensions: AEXMLElement?
            
            var impressions: [URIIdentifier] = []
            // Contains all creative elements within an InLine or Wrapper Ad
            public var creatives: [Creative] = []
            
        }
        
        // Wraps each creative element within an InLine or Wrapper Ad
        public struct Creative {
            init?(id: String?, sequence: String?, adId: String?, companionAdsRequired: String?) {
                self.id = id
                self.sequence = sequence?.asXMLInt()
                self.adId = adId
                self.companionAdsRequired = companionAdsRequired
            }
            
            var id: String?
            // The preferred order in which multiple Creatives should be displayed
            var sequence: Int?
            // Ad-ID for the creative (formerly ISCI)
            var adId: String?
            var companionAdsRequired: String?
            
            public var linears: [Linear] = []
            var companions: [Companion] = []
            var nonLinears: [NonLinear] = []
            var nonLinearTrackingEvents: [TrackURIIdentifier] = []
            
            class IFrameResource: URIIdentifier, VASTResource {
            }
            
            class StaticResource: URIIdentifier, VASTResource {
                init?(creativeType: String?, uri: String?, id: String?) {
                    super.init(uri: uri, id: id)
                    
                    guard let uri = uri, let creativeType = creativeType else {
                        return nil
                    }
                    
                    self.creativeType = creativeType
                    self.uri = uri
                    self.id = id
                }
                // Mime type of static resource (if static resource)
                var creativeType: String!
            }
            
            class HTMLResource: URIIdentifier, VASTResource {
                // Specifies whether the HTML is XML-encoded
                var xmlEncoded: Bool?
                
                init?(uri: String?, id: String?, xmlEncoded: String?) {
                    super.init(uri: uri, id: id)
                    
                    guard let uri = uri else {
                        return nil
                    }
                    
                    self.xmlEncoded = xmlEncoded == "true" || xmlEncoded == "1" ? true : false
                    self.uri = uri
                    self.id = id
                }
            }
            
            enum ClickType {
                // URLs to ping when user clicks on the the icon.
                case ClickTracking,
                // URL to open as destination page when user clicks on the icon.
                ClickThrough,
                // URLs to request on custom events such as hotspotted video
                CustomClick,
                UnKnown
            }
            
            class Click: URIIdentifier {
                var type: ClickType = ClickType.UnKnown
            }
            
            public class MediaFile: URIIdentifier {
                init?(delivery: String?, type: String?, bitrate: String?, minBitrate: String?, maxBitrate: String?, width: String?, height: String?, scalable: String?, maintainAspectRatio: String?, codec: String?, apiFramework: String?, uri: String?, id: String?) {
                    super.init(uri: uri, id: id)
                    guard let delivery = delivery, let width = width, let height = height else {
                        return nil
                    }
                    self.delivery = delivery
                    self.type = type
                    self.bitrate = bitrate
                    self.minBitrate = minBitrate
                    self.maxBitrate = maxBitrate
                    self.width = width.asXMLInt()
                    self.height = height.asXMLInt()
                    self.scalable = scalable?.asXMLBool()
                    self.maintainAspectRatio = maintainAspectRatio?.asXMLBool()
                    self.codec = codec
                    self.apiFramework = apiFramework
                    
                }
                // Method of delivery of ad
                var delivery: String!
                // MIME type. Popular MIME types include, but are not limited to “video/x-ms-wmv” for Windows Media, and “video/x-flv” for Flash Video. Image ads or interactive ads can be included in the MediaFiles section with appropriate Mime MIME type. Popular MIME types include, but are not limited to “video/x-ms-wmv” for Windows Media, and “video/x-flv” for Flash Video. Image ads or interactive ads can be included in the MediaFiles section with appropriate Mime types
                var type: String!
                
                // Bitrate of encoded video in Kbps. If bitrate is supplied, minBitrate and maxBitrate should not be supplied.
                var bitrate: String?
                // Minimum bitrate of an adaptive stream in Kbps. If minBitrate is supplied, maxBitrate must be supplied and bitrate should not be supplied.
                var minBitrate: String?
                // Maximum bitrate of an adaptive stream in Kbps. If maxBitrate is supplied, minBitrate must be supplied and bitrate should not be supplied.
                var maxBitrate: String?
                var width: Int!
                var height: Int!
                // Whether it is acceptable to scale the image.
                var scalable: Bool?
                // The apiFramework defines the method to use for communication if the MediaFile is interactive. Suggested values for this element are “VPAID”, “FlashVars” (for Flash/Flex), “initParams” (for Silverlight) and “GetVariables”
                // (variables placed in key/value pairs on the asset request).
                var maintainAspectRatio: Bool?
                var codec: String?
                var apiFramework: String?
            }
            
            struct Icon {
                // Identifies the industry initiative that the icon supports.
                var program: String!
                var width: Int!
                var height: Int!
                // The horizontal alignment location (in pixels) or a specific alignment.
                var xPosition: Int!
                // The vertical alignment location (in pixels) or a specific alignment.
                var yPosition: Int!
                // Start time at which the player should display the icon. Expressed in standard time format hh:mm:ss.
                var offset: String?
                // The duration for which the player must display the icon. Expressed in standard time format hh:mm:ss.
                var duration: String?
                // The apiFramework defines the method to use for communication with the icon element
                var apiFramework: String?
                
                init?(program: String?, width: String?, height: String?, xPosition: String?, yPosition: String?, offset: String?, duration: String?, apiFramework: String?) {
                    guard
                        let program = program, let width = width, let height = height, let xPosition = xPosition, let yPosition = yPosition
                        else { return }
                    
                    self.program = program
                    self.width = width.asXMLInt()
                    self.height = height.asXMLInt()
                    self.xPosition = xPosition.asXMLInt()
                    self.yPosition = yPosition.asXMLInt()
                    self.offset = offset
                    self.duration = duration
                    self.apiFramework = apiFramework
                }
                
                var resource: VASTResource!
                var clickThrough: URIIdentifier?
                var clickTracking: [URIIdentifier] = []
                // URLs to ping when icon is shown.
                var viewTracking: [URIIdentifier] = []
                
            }
            
            public struct Linear {
                init?(skipoffset: String?, duration: String?) {
                    guard duration != nil else {
                        return nil
                    }
                    
                    self.skipoffset = skipoffset
                    self.duration = duration!
                }
                
                // The time at which the ad becomes skippable, if absent, the ad is not skippable.
                var skipoffset: String?
                // Any number of icons representing advertising industry initiatives.
                var icons: [Icon] = []
                var creativeExtensions: AEXMLElement?
                // Duration in standard time format, hh:mm:ss
                var duration: String
                var trackingEvents: [TrackURIIdentifier] = []
                var parameters: Parameter?
                var clickThrough: URIIdentifier?
                var clickTracking: [URIIdentifier] = []
                var customClick: [URIIdentifier] = []
                public var mediaFiles: [MediaFile] = []
            }
            
            struct NonLinear {
                init?(id: String?, width: String?, height: String?, expandedWidth: String?, expandedHeight: String?, scalable: String?, maintainAspectRatio: String?, minSuggestedDuration: String?, apiFramework: String?, clickThrough: URIIdentifier?, resource: VASTResource?, parameters: Parameter?) {
                    guard let width = width, let height = height, let resource = resource else {
                        return nil
                    }
                    
                    self.id = id
                    self.width = width.asXMLInt()
                    self.height = height.asXMLInt()
                    self.expandedWidth = expandedWidth?.asXMLInt()
                    self.expandedHeight = expandedHeight?.asXMLInt()
                    self.scalable = scalable?.asXMLBool()
                    self.maintainAspectRatio = maintainAspectRatio?.asXMLBool()
                    self.minSuggestedDuration = minSuggestedDuration
                    self.apiFramework = apiFramework
                    self.clickThrough = clickThrough
                    self.resource = resource
                    self.parameters = parameters
                    
                }
                var id: String?
                var width: Int!
                var height: Int!
                var expandedWidth: Int?
                var expandedHeight: Int?
                var scalable: Bool?
                var maintainAspectRatio: Bool?
                var minSuggestedDuration: String?
                var apiFramework: String?
                
                var clickThrough: URIIdentifier?
                var resource: VASTResource!
                var parameters: Parameter?
                
                var extensions: [AEXMLElement] = []
                var clickTracking: [URIIdentifier] = []
                
            }
            
            struct Companion {
                init?(id: String?, width: String?, height: String?, assetWidth: String?, assetHeight: String?, expandedWidth: String?, expandedHeight: String?, apiFramework: String?, adSlotId: String?, resource: VASTResource?, clickThrough: URIIdentifier?, clickTracking: URIIdentifier?, altText: String?, parameters: Parameter?) {
                    guard let width = width, let height = height, let resource = resource else {
                        return nil
                    }
                    
                    self.id = id
                    self.width = width.asXMLInt()
                    self.height = height.asXMLInt()
                    self.assetWidth = assetWidth?.asXMLInt()
                    self.assetHeight = assetHeight?.asXMLInt()
                    self.expandedWidth = expandedWidth?.asXMLInt()
                    self.expandedHeight = expandedHeight?.asXMLInt()
                    self.apiFramework = apiFramework
                    self.adSlotId = adSlotId
                    self.resource = resource
                    self.clickThrough = clickThrough
                    self.clickTracking = clickTracking
                    self.altText = altText
                    self.parameters = parameters
                }
                
                var id: String?
                // Pixel dimensions of companion slot
                var width: Int!
                var height: Int!
                // Pixel dimensions of the companion asset
                var assetWidth: Int?
                var assetHeight: Int?
                // Pixel dimensions of expanding companion ad when in expanded state
                var expandedWidth: Int?
                var expandedHeight: Int?
                // The apiFramework defines the method to use for communication with the companion
                var apiFramework: String?
                // Used to match companion creative to publisher placement areas on the page.
                var adSlotId: String?
                var clickThrough: URIIdentifier?
                var clickTracking: URIIdentifier?
                var resource: VASTResource!
                var altText: String?
                var parameters: AdObject.Parameter?
                
                var extensions: [AEXMLElement] = []
                var trackingEvents: [TrackURIIdentifier] = []
                
            }
        }
    }
}

extension AEXMLElement {
    func Creatives() -> [Vast.AdObject.Creative] {
        var creatives: [Vast.AdObject.Creative] = []
        if let creativeXMLList = self["Creatives"]["Creative"].all {
            for creativeXML in creativeXMLList {
                
                if var creative = Vast.AdObject.Creative(id: creativeXML.attributes["id"], sequence: creativeXML.attributes["sequence"], adId: creativeXML.attributes["AdID"], companionAdsRequired: creativeXML["CompanionAds"].attributes["required"]) {
                    creative.linears = creativeXML.linears()
                    creative.companions = creativeXML.companions()
                    creative.nonLinears = creativeXML.nonLinears()
                    creatives.append(creative)
                }
                
            }
        }
        
        return creatives
    }
    
    func Impressions() -> [Vast.AdObject.URIIdentifier] {
        var impressions: [Vast.AdObject.URIIdentifier] = []
        
        if let itemList = self["Impression"].all {
            for item in itemList {
                if let uri = item.uri() {
                    impressions.append(uri)
                }
            }
        }
        
        return impressions
    }
    
    func trackingURI() -> Vast.AdObject.TrackURIIdentifier? {
        return Vast.AdObject.TrackURIIdentifier(event: self.attributes["event"], offset: self.attributes["offset"], uri: self.value, id: self.attributes["id"])
    }
    
    func uri() -> Vast.AdObject.URIIdentifier? {
        return Vast.AdObject.URIIdentifier(uri: self.value, id: self.attributes["id"])
    }
    
    func media() -> Vast.AdObject.Creative.MediaFile? {
        return Vast.AdObject.Creative.MediaFile(delivery: self.attributes["delivery"], type: self.attributes["type"], bitrate: self.attributes["bitrate"], minBitrate: self.attributes["minBitrate"], maxBitrate: self.attributes["maxBitrate"], width: self.attributes["width"], height: self.attributes["height"], scalable: self.attributes["scalable"], maintainAspectRatio: self.attributes["maintainAspectRatio"], codec: self.attributes["codec"], apiFramework: self.attributes["apiFramework"], uri: self.value, id: self.attributes["id"])
    }
    
    func trackingList() -> [Vast.AdObject.TrackURIIdentifier] {
        var results: [Vast.AdObject.TrackURIIdentifier] = []
        if let all = self["TrackingEvents"]["Tracking"].all {
            for item in all {
                if let uri = item.trackingURI() {
                    results.append(uri)
                }
            }
        }
        
        return results
    }
    
    func uriList(name: String) -> [Vast.AdObject.URIIdentifier] {
        var results: [Vast.AdObject.URIIdentifier] = []
        if let all = self[name].all {
            for item in all {
                if let uri = item.uri() {
                    results.append(uri)
                }
            }
        }
        
        return results
    }
    
    func nonLinears() -> [Vast.AdObject.Creative.NonLinear] {
        var nlinears: [Vast.AdObject.Creative.NonLinear] = []
        
        if let nlinearXMLList = self["NonLinearAds"]["NonLinear"].all {
            for nlinearXML in nlinearXMLList {
                if var linear = Vast.AdObject.Creative.NonLinear(id: nlinearXML.attributes["id"], width: nlinearXML.attributes["width"], height: nlinearXML.attributes["height"], expandedWidth: nlinearXML.attributes["expandedWidth"], expandedHeight: nlinearXML.attributes["expandedHeight"], scalable: nlinearXML.attributes["scalable"], maintainAspectRatio: nlinearXML.attributes["maintainAspectRatio"], minSuggestedDuration: nlinearXML.attributes["minSuggestedDuration"], apiFramework: nlinearXML.attributes["apiFramework"], clickThrough: nlinearXML["NonLinearClickThrough"].uri(), resource: nlinearXML.resource(), parameters: nlinearXML.parameters()) {
                    linear.clickTracking = nlinearXML.uriList(name: "NonLinearClickTracking")
                    linear.extensions = nlinearXML["CreativeExtensions"]["CreativeExtension"].all ?? []
                    nlinears.append(linear)
                }
            }
        }
        return nlinears
    }
    
    func companions() -> [Vast.AdObject.Creative.Companion] {
        var companions: [Vast.AdObject.Creative.Companion] = []
        
        if let companionXMLList = self["CompanionAds"]["Companion"].all {
            for companionXML in companionXMLList {
                if var companion = Vast.AdObject.Creative.Companion(id: companionXML.attributes["id"], width: companionXML.attributes["width"], height: companionXML.attributes["height"], assetWidth: companionXML.attributes["assetWidth"], assetHeight: companionXML.attributes["assetHeight"], expandedWidth: companionXML.attributes["expandedWidth"], expandedHeight: companionXML.attributes["expandedHeight"], apiFramework: companionXML.attributes["apiFramework"], adSlotId: companionXML.attributes["adSlotId"], resource: companionXML.resource(), clickThrough: companionXML["CompanionClickThrough"].uri(), clickTracking: companionXML["CompanionClickTracking"].uri(), altText: companionXML["AltText"].value, parameters: companionXML.parameters()) {
                    companion.trackingEvents = companionXML.trackingList()
                    companion.extensions = companionXML["CreativeExtensions"]["CreativeExtension"].all ?? []
                    
                    companions.append(companion)
                    
                }
            }
        }
        return companions
    }
    
    func parameters() -> Vast.AdObject.Parameter? {
        return Vast.AdObject.Parameter(value: self["AdParameters"].value, xmlEncoded: self["AdParameters"].attributes["xmlEncoded"])
    }
    
    func linears() -> [Vast.AdObject.Creative.Linear] {
        var linears: [Vast.AdObject.Creative.Linear] = []
        if let linearXMLList = self["Linear"].all {
            for linearXML in linearXMLList {
                
                if var linear = Vast.AdObject.Creative.Linear(skipoffset: linearXML.attributes["skipoffset"], duration: linearXML["Duration"].value) {
                    linear.icons = linearXML.Icons()
                    linear.trackingEvents = linearXML.trackingList()
                    linear.parameters = Vast.AdObject.Parameter(value: linearXML["AdParameters"].value, xmlEncoded: linearXML["AdParameters"].attributes["xmlEncoded"])
                    linear.clickThrough = linearXML["VideoClicks"]["ClickThrough"].uri()
                    linear.clickTracking = linearXML["VideoClicks"].uriList(name: "ClickTracking")
                    linear.customClick = linearXML["VideoClicks"].uriList(name: "CustomClick")
                    linear.mediaFiles = linearXML.mediaFiles()
                    linears.append(linear)
                }
            }
        }
        
        return linears
    }
    
    func mediaFiles() -> [Vast.AdObject.Creative.MediaFile] {
        var results: [Vast.AdObject.Creative.MediaFile] = []
        if let all = self["MediaFiles"]["MediaFile"].all {
            for item in all {
                if let uri = item.media() {
                    results.append(uri)
                }
            }
        }
        
        return results
    }
    
    func resource() -> VASTResource? {
        for item in self.children {
            switch item.name {
            case "StaticResource":
                return Vast.AdObject.Creative.StaticResource(creativeType: item.attributes["creativeType"], uri: item.value, id: item.attributes["id"])
                
            case "IFrameResource":
                return Vast.AdObject.Creative.IFrameResource(uri: item.value, id: item.attributes["id"])
                
            case "HTMLResource":
                return Vast.AdObject.Creative.HTMLResource(uri: item.value, id: item.attributes["id"], xmlEncoded: item.attributes["xmlEncoded"])
                
            default:
                break
            }
        }
        
        return nil
    }
    
    func Icons() -> [Vast.AdObject.Creative.Icon] {
        var icons: [Vast.AdObject.Creative.Icon] = []
        
        if let itemList = self["Icons"]["Icon"].all {
            for item in itemList {
                // uri: item.value, id: item.attributes["id"]
                if var icon = Vast.AdObject.Creative.Icon(program: item.attributes["program"], width: item.attributes["width"], height: item.attributes["height"], xPosition: item.attributes["xPosition"], yPosition: item.attributes["yPosition"], offset: item.attributes["offset"], duration: item.attributes["duration"], apiFramework: item.attributes["apiFramework"]) {
                    icon.clickThrough = item["IconClicks"]["IconClickThrough"].uri()
                    icon.clickTracking = item["IconClicks"].uriList(name: "IconClickTracking")
                    icon.viewTracking = item.uriList(name: "IconViewTracking")
                    icon.resource = item.resource()
                    icons.append(icon)
                }
            }
        }
        
        return icons
    }
}
