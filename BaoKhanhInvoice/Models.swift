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

struct SavedInvoiceItem: Codable, Equatable {
    var name: String
    var quantity: Int
    var price: Int

    var lineTotal: Int {
        max(1, quantity) * price
    }
}

struct SavedInvoiceRecord: Codable, Identifiable, Equatable {
    var id: String { invoice_code }
    var invoice_code: String
    var order_code: String
    var invoice_date_vn: String?
    var customer_name: String
    var items: [SavedInvoiceItem]
    var subtotal: Int
    var discount: Int
    var total_amount: Int
    var payment_status: String
    var status_text: String?
    var paid_at_vn: String?
    var qr_text: String?
    var saved_at: String

    func toInvoiceInfo() -> InvoiceInfo {
        InvoiceInfo(
            id: nil,
            invoice_code: invoice_code,
            order_code: order_code,
            invoice_date_vn: invoice_date_vn,
            subtotal: subtotal,
            discount: discount,
            total_amount: total_amount,
            payment_status: payment_status,
            status_text: status_text,
            paid_at: nil,
            paid_at_vn: paid_at_vn
        )
    }

    func toLocalItems() -> [LocalInvoiceItem] {
        let rows = items.map { item in
            LocalInvoiceItem(
                name: item.name,
                priceText: String(item.price),
                quantity: max(1, item.quantity)
            )
        }
        return rows.isEmpty ? [LocalInvoiceItem(name: "", priceText: "")] : rows
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

struct InvoiceInfo: Decodable, Equatable {
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

    init(
        id: Int?,
        invoice_code: String,
        order_code: String,
        invoice_date_vn: String?,
        subtotal: Int?,
        discount: Int?,
        total_amount: Int,
        payment_status: String,
        status_text: String?,
        paid_at: String?,
        paid_at_vn: String?
    ) {
        self.id = id
        self.invoice_code = invoice_code
        self.order_code = order_code
        self.invoice_date_vn = invoice_date_vn
        self.subtotal = subtotal
        self.discount = discount
        self.total_amount = total_amount
        self.payment_status = payment_status
        self.status_text = status_text
        self.paid_at = paid_at
        self.paid_at_vn = paid_at_vn
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
