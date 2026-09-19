import { Controller } from "@hotwired/stimulus"

// Renders the OpenAPI description with Swagger UI, the reference renderer.
//
// The bundle is 1.6 MB, so it is fetched only when this page is opened, never
// on any other page. It is served from this node rather than a CDN: a ledger
// whose argument is that you should not have to trust an unaccountable party
// should not put someone else's script on its own documentation.
//
// Only GET is submittable. A write to this API carries an Ed25519 signature
// over the canonical envelope, which a browser form cannot produce, so an
// executable "Try it out" button on a write would be a lie.
export default class extends Controller {
  static values = { url: String, script: String, css: String }

  connect() {
    this.load().then(() => this.render()).catch(() => this.fail())
  }

  load() {
    if (window.SwaggerUIBundle) return Promise.resolve()

    window.swaggerUiLoading ||= new Promise((resolve, reject) => {
      const style = document.createElement("link")
      style.rel = "stylesheet"
      style.href = this.cssValue
      document.head.appendChild(style)

      const script = document.createElement("script")
      script.src = this.scriptValue
      script.onload = resolve
      script.onerror = reject
      document.head.appendChild(script)
    })
    return window.swaggerUiLoading
  }

  render() {
    window.SwaggerUIBundle({
      url: this.urlValue,
      domNode: this.element,
      deepLinking: true,
      docExpansion: "list",
      defaultModelsExpandDepth: 1,
      displayRequestDuration: true,
      supportedSubmitMethods: ["get"],
      tryItOutEnabled: true,
      syntaxHighlight: { activated: true, theme: "idea" }
    })
  }

  fail() {
    this.element.innerHTML =
      '<p class="flash">The renderer did not load. The description itself is at ' +
      `<a href="${this.urlValue}"><code>${this.urlValue}</code></a>.</p>`
  }
}
