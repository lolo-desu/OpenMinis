import Foundation
import CoreLocation

@objc public class WeatherOffloadBridge: NSObject {
    @objc public static func fetchWeather(
        forLatitude lat: Double,
        longitude lng: Double,
        completion: @escaping (NSDictionary?, Error?) -> Void
    ) {
        let err = NSError(
            domain: "WeatherOffload",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "WeatherKit is not available on iOS 15."]
        )
        completion(nil, err)
    }
}
