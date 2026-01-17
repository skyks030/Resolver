import Foundation

var WEBHOOK_URL_simon = "https://prod-132.westeurope.logic.azure.com:443/workflows/0e729775c9934cdc8f977c11e8699b25/triggers/manual/paths/invoke?api-version=2016-06-01&sp=%2Ftriggers%2Fmanual%2Frun&sv=1.0&sig=KPyErjK1CNb3iTpD3N_auMDYTF95xjSe7uaCfzfUSrE"

var WEBHOOK_URL_sky = "https://prod-52.westeurope.logic.azure.com:443/workflows/b3e5ac260605402d993614b3ae30047f/triggers/manual/paths/invoke?api-version=2016-06-01&sp=%2Ftriggers%2Fmanual%2Frun&sv=1.0&sig=8rVW6W0GQkEidvHA6KwTw9yh3FPGnFPoftEQJ0Tan6M"


print("moin")

func sendTeamsMessage(message: String) {
    let webhookURL = URL("https://prod-52.westeurope.logic.azure.com:443/workflows/b3e5ac260605402d993614b3ae30047f/triggers/manual/paths/invoke?api-version=2016-06-01&sp=%2Ftriggers%2Fmanual%2Frun&sv=1.0&sig=8rVW6W0GQkEidvHA6KwTw9yh3FPGnFPoftEQJ0Tan6M")!

    var request = URLRequest(url: webhookURL)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    let body: [String: Any] = ["text": message]
    request.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [])

    let task = URLSession.shared.dataTask(with: request) { data, response, error in
        if let error = error {
            print("❌ Fehler beim Senden: \(error)")
            return
        }

        if let httpResponse = response as? HTTPURLResponse {
            if (200...299).contains(httpResponse.statusCode) {
                print("✅ Nachricht gesendet")
            } else {
                print("❌ Unerwarteter Statuscode: \(httpResponse.statusCode)")
            }
        }
    }

    task.resume()
}

sendTeamsMessage(message: "✅ Done.")
