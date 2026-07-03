import Foundation

struct LocalInvoiceItem: Identifiable, Equatable {
    let id = UUID()
    var name: String
    var priceText: String
    var quantity: Int = 1

    var price: Int {
        Money.parse(priceText)
    }

    var lineTotal: Int {
        max(1, quantity) * price
    }
}

struct CreateInvoiceRequest: Encodable {
    let customer_name: String
    let discount: Int
    let items: [CreateInvoiceItem]
}

struct CreateInvoiceItem: Encodable {
    let name: String
    let quantity: Int
    let price: Int
}

struct CreateInvoiceResponse: Decodable {
    let success: Bool
    let invoice: InvoiceInfo
    let payment: PaymentInfo
}

struct PaymentInfo: Decodable {
    let paymentLinkId: String?
    let checkoutUrl: String?
    let qrCode: String?
}

struct InvoiceInfo: Decodable {
    let id: Int?
    let invoice_code: String
    let order_code: String
    let invoice_date_vn: String?
    let subtotal: Int?
    let discount: Int?
    let total_amount: Int
    let payment_status: String
    let status_text: String?
    let paid_at: String?
    let paid_at_vn: String?

    enum CodingKeys: String, CodingKey {
        case id, invoice_code, order_code, invoice_date_vn, subtotal, discount, total_amount, payment_status, status_text, paid_at, paid_at_vn
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try? c.decodeIfPresent(Int.self, forKey: .id)
        invoice_code = (try? c.decode(String.self, forKey: .invoice_code)) ?? ""
        if let s = try? c.decode(String.self, forKey: .order_code) {
            order_code = s
        } else if let i = try? c.decode(Int.self, forKey: .order_code) {
            order_code = String(i)
        } else {
            order_code = ""
        }
        invoice_date_vn = try? c.decodeIfPresent(String.self, forKey: .invoice_date_vn)
        subtotal = try? c.decodeIfPresent(Int.self, forKey: .subtotal)
        discount = try? c.decodeIfPresent(Int.self, forKey: .discount)
        total_amount = (try? c.decode(Int.self, forKey: .total_amount)) ?? 0
        payment_status = (try? c.decode(String.self, forKey: .payment_status)) ?? ""
        status_text = try? c.decodeIfPresent(String.self, forKey: .status_text)
        paid_at = try? c.decodeIfPresent(String.self, forKey: .paid_at)
        paid_at_vn = try? c.decodeIfPresent(String.self, forKey: .paid_at_vn)
    }
}

struct StatusResponse: Decodable {
    let success: Bool
    let invoice: InvoiceInfo
}

enum APIError: Error, LocalizedError {
    case badURL
    case server(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .badURL:
            return "API URL không hợp lệ."
        case .server(let msg):
            return msg
        case .invalidResponse:
            return "Dữ liệu API trả về không hợp lệ."
        }
    }
}

enum Money {
    static func parse(_ value: String) -> Int {
        let digits = value.filter { $0.isNumber }
        return Int(digits) ?? 0
    }

    static func format(_ amount: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = "."
        formatter.decimalSeparator = ","
        formatter.maximumFractionDigits = 0
        let text = formatter.string(from: NSNumber(value: amount)) ?? "0"
        return "\(text)đ"
    }

    static func inputFormat(_ value: String) -> String {
        let amount = parse(value)
        if amount == 0 { return "" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = "."
        formatter.decimalSeparator = ","
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: amount)) ?? ""
    }
}
