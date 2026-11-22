import Foundation

/// Optional metadata lookup via the free Open Library API. Only the typed query is sent.
struct OpenLibraryResult: Identifiable, Hashable {
    let id: String
    let title: String
    let author: String
    let year: Int?
    let pages: Int?
    let isbn: String?
    let coverID: Int?
    let subjects: [String]
    var coverURL: URL? { coverID.map { URL(string: "https://covers.openlibrary.org/b/id/\($0)-L.jpg")! } }
}

enum OpenLibrary {
    private struct Response: Decodable {
        struct Doc: Decodable {
            let key: String
            let title: String?
            let author_name: [String]?
            let first_publish_year: Int?
            let number_of_pages_median: Int?
            let isbn: [String]?
            let cover_i: Int?
            let subject: [String]?
        }
        let docs: [Doc]
    }

    static func search(_ query: String) async throws -> [OpenLibraryResult] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        var c = URLComponents(string: "https://openlibrary.org/search.json")!
        let digits = q.filter(\.isNumber)
        let isISBN = (digits.count == 10 || digits.count == 13) && q.allSatisfy { $0.isNumber || $0 == "-" || $0 == "X" || $0 == " " }
        c.queryItems = [
            URLQueryItem(name: isISBN ? "isbn" : "q", value: isISBN ? digits : q),
            URLQueryItem(name: "limit", value: "12"),
            URLQueryItem(name: "fields", value: "key,title,author_name,first_publish_year,number_of_pages_median,isbn,cover_i,subject"),
        ]
        var req = URLRequest(url: c.url!)
        req.setValue("Readscape/1.0 (macOS reading app)", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 15
        let (data, _) = try await URLSession.shared.data(for: req)
        return try JSONDecoder().decode(Response.self, from: data).docs.map { d in
            OpenLibraryResult(id: d.key, title: d.title ?? "Untitled", author: d.author_name?.joined(separator: ", ") ?? "",
                              year: d.first_publish_year, pages: d.number_of_pages_median,
                              isbn: d.isbn?.first { $0.count == 13 } ?? d.isbn?.first, coverID: d.cover_i,
                              subjects: Array((d.subject ?? []).prefix(3)).map { $0.lowercased() })
        }
    }

    static func cover(_ url: URL) async -> Data? {
        try? await URLSession.shared.data(from: url).0
    }

    /// Returns nil when Open Library has no cover for this ISBN (default=false makes it 404 instead of a blank image).
    static func cover(isbn: String) async -> Data? {
        guard let url = URL(string: "https://covers.openlibrary.org/b/isbn/\(isbn)-L.jpg?default=false"),
              let (data, resp) = try? await URLSession.shared.data(from: url),
              (resp as? HTTPURLResponse)?.statusCode == 200, data.count > 1000 else { return nil }
        return data
    }
}
