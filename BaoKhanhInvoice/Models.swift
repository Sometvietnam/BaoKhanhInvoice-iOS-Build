import Foundation

struct LocalInvoiceItem: Identifiable, Equatable {
    let id = UUID()
    var name: String
    var priceText: String
    var quantityText: String = "1"

    var price: Int {
        Money.parse(priceText)
    }

    var quantity: Double {
        Quantity.parse(quantityText)
    }

    var safeQuantity: Double {
        max(0.000001, quantity)
    }

    var lineTotal: Int {
        Int((safeQuantity * Double(price)).rounded())
    }
}

struct SavedInvoiceItem: Codable, Equatable {
    var name: String
    var quantity: Double
    var price: Int

    enum CodingKeys: String, CodingKey {
        case name, quantity, price
    }

    init(name: String, quantity: Double, price: Int) {
        self.name = name
        self.quantity = quantity
        self.price = price
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        if let d = try? c.decode(Double.self, forKey: .quantity) {
            quantity = d
        } else if let i = try? c.decode(Int.self, forKey: .quantity) {
            quantity = Double(i)
        } else if let s = try? c.decode(String.self, forKey: .quantity) {
            quantity = Quantity.parse(s)
        } else {
            quantity = 1
        }
        price = (try? c.decode(Int.self, forKey: .price)) ?? 0
    }

    var safeQuantity: Double {
        max(0.000001, quantity)
    }

    var lineTotal: Int {
        Int((safeQuantity * Double(price)).rounded())
    }
}

struct SavedInvoiceRecord: Codable, Identifiable, Equatable {
    var id: String { invoice_code }
    var invoice_code: String
    var order_code: String
    var invoice_date_vn: String?
    var customer_name: String
    var customer_phone: String?
    var items: [SavedInvoiceItem]
    var subtotal: Int
    var discount: Int
    var total_amount: Int
    var payment_status: String
    var status_text: String?
    var paid_at_vn: String?
    var qr_text: String?
    var saved_at: String

    var isPaid: Bool {
        payment_status.uppercased() == "PAID"
    }

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
            paid_at_vn: paid_at_vn,
            customer_name: customer_name,
            customer_phone: customer_phone
        )
    }

    func toLocalItems() -> [LocalInvoiceItem] {
        let rows = items.map { item in
            LocalInvoiceItem(
                name: item.name,
                priceText: String(item.price),
                quantityText: Quantity.format(item.quantity)
            )
        }
        return rows.isEmpty ? [LocalInvoiceItem(name: "", priceText: "")] : rows
    }
}

struct CreateInvoiceRequest: Encodable {
    let customer_name: String
    let customer_phone: String
    let discount: Int
    let items: [CreateInvoiceItem]
}

struct UpdateInvoiceRequest: Encodable {
    let invoice_code: String
    let order_code: String
    let customer_name: String
    let customer_phone: String
    let discount: Int
    let items: [CreateInvoiceItem]
}

struct DeleteInvoiceRequest: Encodable {
    let invoice_code: String
    let order_code: String
}

struct CreateInvoiceItem: Encodable {
    let name: String
    let quantity: Double
    let price: Int
}

struct CreateInvoiceResponse: Decodable {
    let success: Bool
    let invoice: InvoiceInfo
    let payment: PaymentInfo
}

struct BasicResponse: Decodable {
    let success: Bool
    let message: String?
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
    let customer_name: String?
    let customer_phone: String?
    let subtotal: Int?
    let discount: Int?
    let total_amount: Int
    let payment_status: String
    let status_text: String?
    let paid_at: String?
    let paid_at_vn: String?

    enum CodingKeys: String, CodingKey {
        case id, invoice_code, order_code, invoice_date_vn, customer_name, customer_phone, subtotal, discount, total_amount, payment_status, status_text, paid_at, paid_at_vn
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
        paid_at_vn: String?,
        customer_name: String? = nil,
        customer_phone: String? = nil
    ) {
        self.id = id
        self.invoice_code = invoice_code
        self.order_code = order_code
        self.invoice_date_vn = invoice_date_vn
        self.customer_name = customer_name
        self.customer_phone = customer_phone
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
        customer_name = try? c.decodeIfPresent(String.self, forKey: .customer_name)
        customer_phone = try? c.decodeIfPresent(String.self, forKey: .customer_phone)
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

struct CustomerContact: Identifiable, Equatable {
    var id: String { key }
    let key: String
    var name: String
    var phone: String
    var totalAmount: Int
    var paidAmount: Int
    var invoiceCount: Int
    var paidInvoiceCount: Int
    var lastPurchaseText: String
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


enum Quantity {
    static func sanitizeInput(_ value: String) -> String {
        var result = ""
        var hasSeparator = false

        for ch in value {
            if ch.isNumber {
                result.append(ch)
            } else if ch == "," || ch == "." {
                if !hasSeparator {
                    if result.isEmpty { result = "0" }
                    result.append(ch)
                    hasSeparator = true
                }
            }
        }

        return result
    }

    static func parse(_ value: String) -> Double {
        let cleaned = sanitizeInput(value)
            .replacingOccurrences(of: ",", with: ".")

        guard let amount = Double(cleaned), amount > 0 else {
            return 1
        }
        return amount
    }

    static func format(_ value: Double) -> String {
        let amount = max(0.000001, value)
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "vi_VN")
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = "."
        formatter.decimalSeparator = ","
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 3
        return formatter.string(from: NSNumber(value: amount)) ?? "1"
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
