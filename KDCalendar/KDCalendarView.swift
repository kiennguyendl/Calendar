//
//  KDCalendarView.swift
//  KDCalendar
//
//  Created by Michael Michailidis on 02/04/2015.
//  Copyright (c) 2015 Karmadust. All rights reserved.
//

import UIKit
import EventKit

let cellReuseIdentifier = "KDCalendarDayCell"

let NUMBER_OF_DAYS_IN_WEEK = 7
let MAXIMUM_NUMBER_OF_ROWS = 6

let HEADER_DEFAULT_SIZE = 40.0

let FIRST_DAY_INDEX = 0
let NUMBER_OF_DAYS_INDEX = 1
let DATE_SELECTED_INDEX = 2

@objc protocol KDCalendarViewDataSource {
    
    func startDate() -> NSDate?
    func endDate() -> NSDate?
    
}

@objc protocol KDCalendarViewDelegate {
    
    optional func calendar(calendar : KDCalendarView, canSelectDate date : NSDate) -> Bool
    func calendar(calendar : KDCalendarView, didScrollToMonth date : NSDate) -> Void
    func calendar(calendar : KDCalendarView, didSelectDate date : NSDate) -> Void
    optional func calendar(calendar : KDCalendarView, didDeselectDate date : NSDate) -> Void
}


class KDCalendarView: UIView, UICollectionViewDataSource, UICollectionViewDelegate {
    
    var dataSource : KDCalendarViewDataSource?
    var delegate : KDCalendarViewDelegate?
    
    var direction : UICollectionViewScrollDirection = .Horizontal {
        didSet {
            if let layout = self.calendarView.collectionViewLayout as? KDCalendarFlowLayout {
                layout.scrollDirection = direction
                self.calendarView.reloadData()
            }
        }
    }
    
    private var startDateCache : NSDate = NSDate()
    private var endDateCache : NSDate = NSDate()
    private var startOfMonthCache : NSDate = NSDate()
    private var todayIndexPath : NSIndexPath?
    
    private(set) var selectedIndexPaths : [NSIndexPath] = [NSIndexPath]()
    private(set) var selectedDates : [NSDate] = [NSDate]()
    
    
    private var eventsByIndexPath : [NSIndexPath:[EKEvent]]?
    var events : [EKEvent]? {
        
        didSet {
            
            if let events = events { // If events are not null
                
                eventsByIndexPath = [NSIndexPath:[EKEvent]]() // Map IndexPath to Event Array
            
                for event in events {
                    
                    let flags: NSCalendarUnit = [NSCalendarUnit.Month, NSCalendarUnit.Day]
                    
                    let distanceFromStartComponent = NSCalendar.currentCalendar().components( // Get the distance of the event from the start
                        flags, fromDate:startOfMonthCache, toDate: event.startDate, options: NSCalendarOptions()
                    )
                    
                    let indexPath = NSIndexPath(forItem: distanceFromStartComponent.day, inSection: distanceFromStartComponent.month)
                    
                    if var eventsList : [EKEvent] = eventsByIndexPath?[indexPath] { // If we have initialized a list for this IndexPath
                        
                        eventsList.append(event) // Simply append
                    }
                    else {
                        
                        eventsByIndexPath?[indexPath] = [event] // Otherwise create the list with the first element
                      
                    }
                    
                } // [for event in events ...]
            
                self.calendarView.reloadData()
                
            } // [if let events ...]
                
            else {
                
                eventsByIndexPath = nil
                
            }
            
        } // didSet
    }
    
    lazy var headerView : KDCalendarHeaderView = {
       
        let hv = KDCalendarHeaderView(frame:CGRectZero)
        
        return hv
        
    }()
    
    lazy var calendarView : UICollectionView = {
     
        let layout = KDCalendarFlowLayout()
        layout.scrollDirection = self.direction;
        layout.minimumInteritemSpacing = 0
        layout.minimumLineSpacing = 0
        
        let cv = UICollectionView(frame: CGRectZero, collectionViewLayout: layout)
        cv.dataSource = self
        cv.delegate = self
        cv.pagingEnabled = true
        cv.backgroundColor = UIColor.clearColor()
        cv.showsHorizontalScrollIndicator = false
        cv.showsVerticalScrollIndicator = false
        cv.allowsMultipleSelection = true
        
        
        return cv
        
    }()
    
    override var frame: CGRect {
        didSet {
            
            var elementFrame = CGRect(x:0.0, y:0.0, width: self.frame.size.width, height:80.0)
            
            self.headerView.frame = elementFrame
            
            elementFrame.origin.y += elementFrame.size.height
            elementFrame.size.height = self.frame.size.height - elementFrame.size.height
            
            self.calendarView.frame = CGRect(x:0.0, y:80.0, width: self.frame.size.width, height:self.frame.size.height - 80.0)
            
            let layout = self.calendarView.collectionViewLayout as! KDCalendarFlowLayout
            
            self.calendarView.collectionViewLayout = layout
            
        }
    }
    
    

    override init(frame: CGRect) {
        super.init(frame : CGRectMake(0.0, 0.0, 200.0, 200.0))
        self.initialSetup()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
    
    override func awakeFromNib() {
        self.initialSetup()
    }
    
    
    
    // MARK: Setup 
    
    func initialSetup() {
        
        
        self.clipsToBounds = true
        
        // Register Class
        self.calendarView.registerClass(KDCalendarDayCell.self, forCellWithReuseIdentifier: cellReuseIdentifier)
        
        
        self.addSubview(self.headerView)
        self.addSubview(self.calendarView)
    }
    
    
    
    // MARK: UICollectionViewDataSource
    
    func numberOfSectionsInCollectionView(collectionView: UICollectionView) -> Int {
        
        // Set the collection view to the correct layout
        let layout = self.calendarView.collectionViewLayout as! UICollectionViewFlowLayout
        layout.itemSize = CGSizeMake(self.calendarView.frame.size.width / CGFloat(NUMBER_OF_DAYS_IN_WEEK), (self.calendarView.frame.size.height - layout.headerReferenceSize.height) / CGFloat(MAXIMUM_NUMBER_OF_ROWS))
     
        self.calendarView.collectionViewLayout = layout
        
       
        if let  startDate = self.dataSource?.startDate(),
                endDate = self.dataSource?.endDate() {
            
            startDateCache = startDate
            endDateCache = endDate
            
            // check if the dates are in correct order
            if NSCalendar.currentCalendar().compareDate(startDate, toDate: endDate, toUnitGranularity: NSCalendarUnit.Nanosecond) != NSComparisonResult.OrderedAscending {
                return 0
            }
            
            // discart day and minutes so that they round off to the first of the month
            let dayOneComponents = NSCalendar.currentCalendar().components( [NSCalendarUnit.Era, NSCalendarUnit.Year, NSCalendarUnit.Month], fromDate: startDateCache)
                    
            // create a GMT set calendar so that the
            if let  gmtCalendar = NSCalendar(calendarIdentifier: NSCalendarIdentifierGregorian),
                    gmtTimeZone = NSTimeZone(abbreviation: "GMT") {
                        
                    gmtCalendar.timeZone = gmtTimeZone
                        
                    if let dateFromDayOneComponents = gmtCalendar.dateFromComponents(dayOneComponents) {
                            
                        startOfMonthCache = dateFromDayOneComponents
                        
                        let today = NSDate()
                        
                        if  startOfMonthCache.compare(today) == NSComparisonResult.OrderedAscending &&
                            endDateCache.compare(today) == NSComparisonResult.OrderedDescending {
                                
                                let differenceFromTodayComponents = NSCalendar.currentCalendar().components([NSCalendarUnit.Month, NSCalendarUnit.Day], fromDate: startOfMonthCache, toDate: NSDate(), options: NSCalendarOptions())
                                
                                self.todayIndexPath = NSIndexPath(forItem: differenceFromTodayComponents.day, inSection: differenceFromTodayComponents.month)
                        
                        }
                        
                        
                        
                        let differenceComponents = NSCalendar.currentCalendar().components(NSCalendarUnit.Month, fromDate: startDateCache, toDate: endDateCache, options: NSCalendarOptions())
                        
                       
                        return differenceComponents.month + 1 // if we are for example on the same month and the difference is 0 we still need 1 to display it
                    }
                        
            }
              
        }
        
        return 0
    }
    
    var monthInfo : [Int:[Int]] = [Int:[Int]]()
    
    func collectionView(collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        
        let monthOffsetComponents = NSDateComponents()
        
        // offset by the number of months
        monthOffsetComponents.month = section;
        
        if let correctMonthForSectionDate = NSCalendar.currentCalendar().dateByAddingComponents(monthOffsetComponents, toDate: startOfMonthCache, options: NSCalendarOptions()) {
            
            let numberOfDaysInMonth = NSCalendar.currentCalendar().rangeOfUnit(NSCalendarUnit.Day, inUnit: NSCalendarUnit.Month, forDate: correctMonthForSectionDate).length
            
            var firstWeekdayOfMonthIndex = NSCalendar.currentCalendar().component(NSCalendarUnit.Weekday, fromDate: correctMonthForSectionDate)
            firstWeekdayOfMonthIndex = firstWeekdayOfMonthIndex - 1 // firstWeekdayOfMonthIndex should be 0-Indexed
            firstWeekdayOfMonthIndex = (firstWeekdayOfMonthIndex + 6) % 7 // push it modularly so that we take it back one day so that the first day is Monday instead of Sunday which is the default
     
            monthInfo[section] = [firstWeekdayOfMonthIndex, numberOfDaysInMonth]
            
            return NUMBER_OF_DAYS_IN_WEEK * MAXIMUM_NUMBER_OF_ROWS // 7 x 6 = 42
        }
        
        return 0
        
    }
    
    func collectionView(collectionView: UICollectionView, cellForItemAtIndexPath indexPath: NSIndexPath) -> UICollectionViewCell {
        
        let dayCell = collectionView.dequeueReusableCellWithReuseIdentifier(cellReuseIdentifier, forIndexPath: indexPath) as! KDCalendarDayCell
     
        let currentMonthInfo : [Int] = monthInfo[indexPath.section]! // we are guaranteed an array by the fact that we reached this line (so unwrap)
        
        let fdIndex = currentMonthInfo[FIRST_DAY_INDEX]
        let nDays = currentMonthInfo[NUMBER_OF_DAYS_INDEX]
        
        if indexPath.item >= fdIndex &&
            indexPath.item < fdIndex + nDays {
            
            dayCell.textLabel.text = String(indexPath.item - fdIndex + 1)
            dayCell.hidden = false
            
        }
        else {
            dayCell.textLabel.text = ""
            dayCell.hidden = true
        }
        
        dayCell.selected = selectedIndexPaths.contains(indexPath)
        
        if indexPath.section == 0 && indexPath.item == 0 {
            self.scrollViewDidEndDecelerating(collectionView)
        }
        
        if let idx = self.todayIndexPath {
            dayCell.isToday = (idx.section == indexPath.section && idx.item + fdIndex == indexPath.item)
        }
        
        if let eventsForDay = self.eventsByIndexPath?[indexPath] {
            
            dayCell.eventsCount = eventsForDay.count
            
        } else {
            dayCell.eventsCount = 0
        }
        
        
        return dayCell
    }
    
    // MARK: UIScrollViewDelegate
    
    
    func scrollViewDidEndDecelerating(scrollView: UIScrollView) {
        
        let cvbounds = self.calendarView.bounds
        
        var page : Int = Int(floor(self.calendarView.contentOffset.x / cvbounds.size.width))

        page = page > 0 ? page : 0
        
        let monthsOffsetComponents = NSDateComponents()
        monthsOffsetComponents.month = page
        
        
        if let yearDate = NSCalendar.currentCalendar().dateByAddingComponents(monthsOffsetComponents, toDate: self.startOfMonthCache, options: NSCalendarOptions()) {
            
            let month = NSCalendar.currentCalendar().component(NSCalendarUnit.Month, fromDate: yearDate)
            
            let monthName = NSDateFormatter().monthSymbols[(month-1) % 12] // 0 indexed array
            
                let year = NSCalendar.currentCalendar().component(NSCalendarUnit.Year, fromDate: yearDate)
                
            
                self.headerView.monthLabel.text = monthName + " " + String(year)
                
            
                if let delegate = self.delegate {
                
                    delegate.calendar(self, didScrollToMonth: yearDate)
            
                }
            
        }
    }
    
    
    
    // MARK: UICollectionViewDelegate
    
    private var dateBeingSelectedByUser : NSDate?
    func collectionView(collectionView: UICollectionView, shouldSelectItemAtIndexPath indexPath: NSIndexPath) -> Bool {
        
        let currentMonthInfo : [Int] = monthInfo[indexPath.section]!
        let firstDayInMonth = currentMonthInfo[0]
        
        let offsetComponents = NSDateComponents()
        offsetComponents.month = indexPath.section
        offsetComponents.day = indexPath.item - firstDayInMonth
        
        if let dateUserSelected = NSCalendar.currentCalendar().dateByAddingComponents(offsetComponents, toDate: self.startOfMonthCache, options: NSCalendarOptions()) {
            
            dateBeingSelectedByUser = dateUserSelected
            
            // Optional protocol method
            if let canSelectFromDelegate = delegate?.calendar?(self, canSelectDate: dateUserSelected) {
                return canSelectFromDelegate
                
            }
            
            return true // it can select any date by default
            
        }
        
        return false // if date is out of scope
        
    }
    
    func collectionView(collectionView: UICollectionView, didDeselectItemAtIndexPath indexPath: NSIndexPath) {
        
        if let
            delegate = self.delegate,
            index = selectedIndexPaths.indexOf(indexPath),
            dateSelectedByUser = dateBeingSelectedByUser {
                
                delegate.calendar?(self, didDeselectDate: dateSelectedByUser)
                
                selectedIndexPaths.removeAtIndex(index)
                selectedDates.removeAtIndex(index)
                
        }
        
    }
    
    func collectionView(collectionView: UICollectionView, didSelectItemAtIndexPath indexPath: NSIndexPath) {
        
        if let
            delegate = self.delegate,
            dateSelectedByUser = dateBeingSelectedByUser {
                
                delegate.calendar(self, didSelectDate: dateSelectedByUser)
                
                // Update model
                selectedIndexPaths.append(indexPath)
                selectedDates.append(dateSelectedByUser)
                
        }
    }
    
    
    func reloadData() {
        self.calendarView.reloadData()
    }

}
