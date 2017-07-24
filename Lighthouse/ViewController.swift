//
//  ViewController.swift
//  Lighthouse
//
//  Created by Joseph Spall on 6/30/17.
//  Copyright © 2017 Lighthouse. All rights reserved.
//

import UIKit
import Alamofire
import Mapbox
import MBProgressHUD
import SwiftyJSON
import SWXMLHash

class ViewController: UIViewController, MGLMapViewDelegate {


    @IBOutlet weak var crimeCount: CrimeCountView!
    @IBOutlet var mapView: MGLMapView!
  
    
    let crimePullURL = "https://www.app-lighthouse.com/app/crimepullcirc.php"
    let MONTH_DIFF_WEIGHT:Double = 100
    var storedCrimes:[Crime] = []
    var storedPins:[MGLPointAnnotation] = []
    var currentCrimeEntryString:String = ""
    var currentDangerLevel:String = ""
    var icon: UIImage!
    var popup: UILabel?

    override func viewDidLoad() {
        super.viewDidLoad()
        
        crimeCount.layer.cornerRadius = 10
        icon = UIImage(named:"crime_icon")
        mapView.delegate = self
        
        
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // Hide the navigation bar on the this view controller
        
        self.navigationController?.setNavigationBarHidden(true, animated: animated)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        // Show the navigation bar on other view controllers
        self.navigationController?.setNavigationBarHidden(false, animated: animated)
    }
    
    
    //Mapbox
    
    func mapViewDidFinishLoadingMap(_ mapView: MGLMapView) {
        mapView.setUserTrackingMode(MGLUserTrackingMode(rawValue: 1)!, animated: true)
        if CLLocationManager.locationServicesEnabled() {
            //TODO handle errors
            switch(CLLocationManager.authorizationStatus()) {
            case .notDetermined, .restricted, .denied:
                createErrorAlert(description: "Location not accessible")
            case .authorizedAlways, .authorizedWhenInUse:
                showLoadingHUD()
               // drawSearchCircle()
                pullCrimes()
                hideLoadingHUD()
                
            }
        } else {
            createErrorAlert(description: "Location services are not enabled")
        }
    }
    
    func mapView(_ mapView: MGLMapView, annotationCanShowCallout annotation: MGLAnnotation) -> Bool {
        // Always try to show a callout when an annotation is tapped.
        return true
    }
    
    func addCrimesToMap(crimeArray:[Crime]){
        guard let style = mapView.style else { return }
        var collection:[MGLPointFeature] = []
        for crime in crimeArray{
            let temp = MGLPointFeature()
            temp.coordinate = crime.location
            temp.attributes = ["date":crime.date,"typeCrime":crime.typeCrime]
            collection.append(temp)
        }
        let shapeCollectionFeature = MGLShapeCollectionFeature(shapes: collection)
        let source = MGLShapeSource(identifier: "clusteredCrimes",shape:shapeCollectionFeature, options: [.clustered: true, .clusterRadius: icon.size.width, .maximumZoomLevelForClustering:20])
        style.addSource(source)
        
        // Use a template image so that we can tint it with the `iconColor` runtime styling property.
        style.setImage(icon.withRenderingMode(.alwaysTemplate), forName: "icon")
        
        // Show unclustered features as icons. The `cluster` attribute is built into clustering-enabled source features.
        let crime = MGLSymbolStyleLayer(identifier: "crime", source: source)
        crime.iconImageName = MGLStyleValue(rawValue: "icon")
        crime.iconColor = MGLStyleValue(rawValue: UIColor.darkGray.withAlphaComponent(0.9))
        crime.predicate = NSPredicate(format: "%K != YES", argumentArray: ["cluster"])
        style.addLayer(crime)
        
        // Color clustered features based on clustered point counts.
        let stops = [
            20:  MGLStyleValue(rawValue: UIColor.lightGray),
            50:  MGLStyleValue(rawValue: UIColor.orange),
            100: MGLStyleValue(rawValue: UIColor.red),
            200: MGLStyleValue(rawValue: UIColor.purple)
        ]
        
        // Show clustered features as circles. The `point_count` attribute is built into clustering-enabled source features.
        let circlesLayer = MGLCircleStyleLayer(identifier: "clusteredCrimes", source: source)
        circlesLayer.circleRadius = MGLStyleValue(rawValue: NSNumber(value: Double(icon.size.width) / 2))
        circlesLayer.circleOpacity = MGLStyleValue(rawValue: 0.75)
        circlesLayer.circleStrokeColor = MGLStyleValue(rawValue: UIColor.white.withAlphaComponent(0.75))
        circlesLayer.circleStrokeWidth = MGLStyleValue(rawValue: 2)
        circlesLayer.circleColor = MGLSourceStyleFunction(interpolationMode: .interval,
                                                          stops: stops,
                                                          attributeName: "point_count",
                                                          options: nil)
        circlesLayer.predicate = NSPredicate(format: "%K == YES", argumentArray: ["cluster"])
        style.addLayer(circlesLayer)
        
        // Label cluster circles with a layer of text indicating feature count. Per text token convention, wrap the attribute in {}.
        let numbersLayer = MGLSymbolStyleLayer(identifier: "clusteredCrimeNumbers", source: source)
        numbersLayer.textColor = MGLStyleValue(rawValue: UIColor.white)
        numbersLayer.textFontSize = MGLStyleValue(rawValue: NSNumber(value: Double(icon.size.width) / 2))
        numbersLayer.iconAllowsOverlap = MGLStyleValue(rawValue: true)
        numbersLayer.text = MGLStyleValue(rawValue: "{point_count}")
        numbersLayer.predicate = NSPredicate(format: "%K == YES", argumentArray: ["cluster"])
        style.addLayer(numbersLayer)
        
        view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap(_:))))
        
    }
    
    func handleTap(_ tap: UITapGestureRecognizer) {
        if tap.state == .ended {
            let point = tap.location(in: tap.view)
            let width = icon.size.width
            let rect = CGRect(x: point.x - width / 2, y: point.y - width / 2, width: width, height: width)
            
            let clusters = mapView.visibleFeatures(in: rect, styleLayerIdentifiers: ["clusteredCrimes"])
            let crimes = mapView.visibleFeatures(in: rect, styleLayerIdentifiers: ["crime"])
            
            if clusters.count > 0 {
                showPopup(false, animated: true)
                let cluster = clusters.first!
                mapView.setCenter(cluster.coordinate, zoomLevel: (mapView.zoomLevel + 1), animated: true)
            } else if crimes.count > 0 {
                let crime = crimes.first!
                
                if popup == nil {
                    popup = UILabel(frame: CGRect(x: 0, y: 0, width: 100, height: 40))
                    popup!.backgroundColor = UIColor.white.withAlphaComponent(0.9)
                    popup!.layer.cornerRadius = 4
                    popup!.layer.masksToBounds = true
                    popup!.textAlignment = .center
                    popup!.lineBreakMode = .byTruncatingTail
                    popup!.font = UIFont.systemFont(ofSize: 16)
                    popup!.textColor = UIColor.black
                    popup!.alpha = 0
                    view.addSubview(popup!)
                }
                popup!.text = (crime.attribute(forKey: "typeCrime")! as! String)
                let size = (popup!.text! as NSString).size(attributes: [NSFontAttributeName: popup!.font])
                popup!.bounds = CGRect(x: 0, y: 0, width: size.width, height: size.height).insetBy(dx: -10, dy: -10)
                let point = mapView.convert(crime.coordinate, toPointTo: mapView)
                popup!.center = CGPoint(x: point.x, y: point.y - 50)
                
                if popup!.alpha < 1 {
                    showPopup(true, animated: true)
                }
                
            } else {
                showPopup(false, animated: true)
            }
        }
    }
    
    func showPopup(_ shouldShow: Bool, animated: Bool) {
        let alpha: CGFloat = (shouldShow ? 1 : 0)
        if animated {
            UIView.animate(withDuration: 0.25) { [unowned self] in
                self.popup?.alpha = alpha
            }
        } else {
            popup?.alpha = alpha
        }
    }
    
    func mapViewRegionIsChanging(_ mapView: MGLMapView) {
        showPopup(false, animated: false)
    }

    func drawSearchCircle() {
        let coordinate:CLLocationCoordinate2D = (mapView.userLocation?.coordinate)!
        let withMeterRadius = Double(UserDefaults.standard.integer(forKey: "radius"))*0.3048
        let degreesBetweenPoints = 8.0
        let numberOfPoints = floor(360.0 / degreesBetweenPoints)
        let distRadians: Double = withMeterRadius / 6371000.0
        let centerLatRadians: Double = coordinate.latitude * Double.pi / 180
        let centerLonRadians: Double = coordinate.longitude * Double.pi / 180
        var coordinates = [CLLocationCoordinate2D]()
        
        for index in 0 ..< Int(numberOfPoints) {
            let degrees: Double = Double(index) * Double(degreesBetweenPoints)
            let degreeRadians: Double = degrees * Double.pi / 180
            let pointLatRadians: Double = asin(sin(centerLatRadians) * cos(distRadians) + cos(centerLatRadians) * sin(distRadians) * cos(degreeRadians))
            let pointLonRadians: Double = centerLonRadians + atan2(sin(degreeRadians) * sin(distRadians) * cos(centerLatRadians), cos(distRadians) - sin(centerLatRadians) * sin(pointLatRadians))
            let pointLat: Double = pointLatRadians * 180 / Double.pi
            let pointLon: Double = pointLonRadians * 180 / Double.pi
            let point: CLLocationCoordinate2D = CLLocationCoordinate2DMake(pointLat, pointLon)
            coordinates.append(point)
        }
        
        let polygon = MGLPolygon(coordinates: &coordinates, count: UInt(coordinates.count))
        polygon.title = "Crime Search Radius"
        mapView.addAnnotation(polygon)
    }
    
    func mapView(_ mapView: MGLMapView, alphaForShapeAnnotation annotation: MGLShape) -> CGFloat {
        return 0.5
    }
    func mapView(_ mapView: MGLMapView, strokeColorForShapeAnnotation annotation: MGLShape) -> UIColor {
        return .white
    }
    
    func mapView(_ mapView: MGLMapView, fillColorForPolygonAnnotation annotation: MGLPolygon) -> UIColor {
        return UIColor(red: 59/255, green: 178/255, blue: 208/255, alpha: 1)
    }
    
    //Alamofire
    
    func pullCrimes(){
        let userLocationObject = mapView?.userLocation
        let currentLat = ((userLocationObject?.coordinate.latitude)!*1000000).rounded()/1000000
        let currentLong = ((userLocationObject?.coordinate.longitude)!*1000000).rounded()/1000000
        var radius = Double(UserDefaults.standard.integer(forKey:"radius"))
        radius /= 364000
        let year = UserDefaults.standard.string(forKey:"year")!
        let param = [
            "curlatitude": currentLat,
            "curlongitude": currentLong,
            "radius": radius,
            "year": year
            ] as [String : Any]
        Alamofire.request(crimePullURL, method: .post, parameters: param).response{ response in
            let error = response.error?.localizedDescription
            if(error == nil) {
                let dataFromPull = response.data!
                let json = JSON(data:dataFromPull)
                let mightError = json["error"]
                if(mightError == JSON.null){
                    let resultsArray = json["results"]
                    for (_,subJson):(String, JSON) in resultsArray {
                        do{
                            let id = subJson["id"].string
                            if !self.storedCrimes.contains(where: {$0.id == id}){
                                try self.storedCrimes.append(Crime(json: subJson))
                            }
                        }
                        catch{
                            print(error)
                            self.createErrorAlert(description: error.localizedDescription)
                        }
                    }
                    self.addCrimesToMap(crimeArray: self.storedCrimes)
                    self.calculateDanger(crimes: self.storedCrimes)
                }
                else{
                    print(mightError.string!)
                    self.createErrorAlert(description: mightError.string!)
                }
                
            }
            else {
                print(error!)
                self.createErrorAlert(description: error!)
            }
        }

    }
    
    func setDate(inputDate:String) -> String{
        let dateFormat = UserDefaults.standard.string(forKey:"format")
        var returnDate:String = ""
        let dateArray = inputDate.components(separatedBy: "-")
        let year:String = dateArray[0]
        let month:String = dateArray[1]
        let restOfArray:String = dateArray[2]
        let dayIndex = restOfArray.index(restOfArray.startIndex, offsetBy:2)
        let day = restOfArray.substring(to: dayIndex)
        if(dateFormat == "MM/DD/YYYY"){
            returnDate = month + "/" + day + "/" + year
        }
        else if(dateFormat == "DD/MM/YYYY"){
            returnDate = day + "/" + month + "/" + year
        }
        else if(dateFormat == "YYYY/MM/DD"){
            returnDate = year + "/" + month + "/" + day
        }
        return returnDate
    }
    
    func checkCrimeEntryXML() -> XMLIndexer{
        if(currentCrimeEntryString == ""){
            if let path = Bundle.main.path(forResource: "crime_weight_storage", ofType: "xml") {
                let url = URL(fileURLWithPath: path)
                do {
                    currentCrimeEntryString = try String(contentsOf: url, encoding: String.Encoding.utf8)
                }
                catch {
                    print(error)
                    //TODO Error Handle if file is unavailable
                }
            }
        }

        return SWXMLHash.parse(currentCrimeEntryString)
    }
    
    func calculateDanger(crimes:[Crime]){
        let currentCrimeEntryXML:XMLIndexer = checkCrimeEntryXML()
        var dangerNumber:Double = 0
        let dateFormatHandle:DateFormatter = DateFormatter()
        dateFormatHandle.dateFormat = "yyyy-MM-dd HH:mm:ss"
        for crime in crimes{
            let crimeType = crime.typeCrime
            do{
                var crimeWeight = try currentCrimeEntryXML["danger"]["crime"].withAttribute("type", crimeType)["weight"].element?.text
                crimeWeight = crimeWeight?.trimmingCharacters(in: .whitespacesAndNewlines)
                let crimeDate:Date = dateFormatHandle.date(from: crime.date)!
                let monthsSince:TimeInterval = Double(Date().timeIntervalSince(crimeDate))/2629743.83
                let monthWeight:Double = pow(M_E,-monthsSince/MONTH_DIFF_WEIGHT)
                let totalWeight:Double = Double(crimeWeight!)!*monthWeight
                dangerNumber += totalWeight
            }
            catch{
                print(error)
                //TODO Error Handle
                
            }
        }
        
        if(dangerNumber <= 3){
            currentDangerLevel = "Safe"
        }
        else if(dangerNumber > 3 && dangerNumber <= 10){
            currentDangerLevel = "Dangerous"
        }
        else if(dangerNumber > 10){
            currentDangerLevel = "Very Dangerous"
        }
        
        if(currentDangerLevel != ""){
            crimeCount.setCrimeLevelLabel(level: currentDangerLevel)
        }
        
    }
    
    //MBProgressHUD
    
    private func showLoadingHUD() {
        let hud = MBProgressHUD.showAdded(to: mapView, animated: true)
        hud.label.text = "Loading..."
    }
    
    private func hideLoadingHUD() {
        MBProgressHUD.hide(for: mapView, animated: true)
    }
    
    //Error Handling
    
    func createErrorAlert(description:String){
        let alert = UIAlertController(title: "Alert", message: description, preferredStyle: UIAlertControllerStyle.alert)
        alert.addAction(UIAlertAction(title: "Ok", style: UIAlertActionStyle.default, handler: nil))
        self.present(alert, animated: true, completion: nil)
    }
    
    
    

}

