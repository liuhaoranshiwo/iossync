import Foundation
import HealthKit

/// HealthKit 读取：今日步数 + 最近一次心率
final class HealthReader: ObservableObject {
    static let shared = HealthReader()

    private let store = HKHealthStore()

    @Published var steps: Double = 0
    @Published var heartRate: Double = 0
    @Published var authorized = false

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private var stepType: HKQuantityType? {
        HKObjectType.quantityType(forIdentifier: .stepCount)
    }
    private var hrType: HKQuantityType? {
        HKObjectType.quantityType(forIdentifier: .heartRate)
    }

    /// 请求读取授权
    func requestAuth(completion: @escaping (Bool) -> Void) {
        guard isAvailable, let stepType = stepType, let hrType = hrType else {
            DispatchQueue.main.async { completion(false) }
            return
        }
        let read: Set<HKObjectType> = [stepType, hrType]
        store.requestAuthorization(toShare: nil, read: read) { [weak self] ok, _ in
            DispatchQueue.main.async {
                self?.authorized = ok
                completion(ok)
            }
        }
    }

    /// 今日累计步数
    func fetchTodaySteps(completion: @escaping (Double) -> Void) {
        guard let stepsType = stepType else {
            DispatchQueue.main.async { completion(0) }
            return
        }
        let start = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)
        let query = HKStatisticsQuery(quantityType: stepsType,
                                      quantitySamplePredicate: predicate,
                                      options: .cumulativeSum) { [weak self] _, result, _ in
            var value = 0.0
            if let sum = result?.sumQuantity() {
                value = sum.doubleValue(for: HKUnit.count())
            }
            DispatchQueue.main.async {
                self?.steps = value
                completion(value)
            }
        }
        store.execute(query)
    }

    /// 最近一条心率（bpm）
    func fetchLatestHeartRate(completion: @escaping (Double) -> Void) {
        guard let hrType = hrType else {
            DispatchQueue.main.async { completion(0) }
            return
        }
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let query = HKSampleQuery(sampleType: hrType,
                                  predicate: nil,
                                  limit: 1,
                                  sortDescriptors: [sort]) { [weak self] _, samples, _ in
            var bpm = 0.0
            if let sample = samples?.first as? HKQuantitySample {
                bpm = sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
            }
            DispatchQueue.main.async {
                self?.heartRate = bpm
                completion(bpm)
            }
        }
        store.execute(query)
    }

    /// 一次性刷新（步数 + 心率），完成后回调
    func fetchAll(completion: @escaping () -> Void) {
        fetchTodaySteps { _ in
            self.fetchLatestHeartRate { _ in
                completion()
            }
        }
    }
}
