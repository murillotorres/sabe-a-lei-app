import Foundation

enum APIConfig {
    // A raiz do domínio tem um .htaccess que intercepta /api antes de chegar
    // na pasta api/ (que por sua vez bloqueia acesso direto, exceto em api/public/).
    // O front controller (api/public/index.php) só é alcançado via /api/public.
    static let baseURL = URL(string: "https://sabealei.alakadim.com.br/api/public")!
}
