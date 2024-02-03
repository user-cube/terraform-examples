# Bucket to store website
resource "google_storage_bucket" "website" {
  name     = "rui-website-bucket"
  location = "EU"
}

# Make the bucket public
resource "google_storage_object_access_control" "public_rule" {
  object = google_storage_bucket_object.static_site_src.name
  bucket = google_storage_bucket.website.name
  role   = "READER"
  entity = "allUsers"
}


# Upload index.html to the bucket
resource "google_storage_bucket_object" "static_site_src" {
  name         = "index.html"                       # This is the name of the file in the bucket
  source       = "../website/index.html"            # This is the name of the file in the local directory
  bucket       = google_storage_bucket.website.name # This is the name of the bucket
  content_type = "text/html"
}

# Reserve static IP for the website
resource "google_compute_global_address" "website_ip" {
  name = "website-lb-ip"
}

# Get managed DNS zone
data "google_dns_managed_zone" "dns_zone" {
  name = "terraform-gcp"
}

# Add IP to DNS
resource "google_dns_record_set" "website_dns" {
  name         = "website.${data.google_dns_managed_zone.dns_zone.dns_name}"
  type         = "A"
  ttl          = 300
  managed_zone = data.google_dns_managed_zone.dns_zone.name
  rrdatas      = [google_compute_global_address.website_ip.address]
}

# Add the bucket as a CDN backend
resource "google_compute_backend_bucket" "website_backend" {
  name        = "website-bucket"
  bucket_name = google_storage_bucket.website.name
  description = "Contains all files for the website"
  enable_cdn  = true
}

# Create a URL map
resource "google_compute_url_map" "website_url_map" {
  name            = "website-url-map"
  default_service = google_compute_backend_bucket.website_backend.self_link
  host_rule {
    hosts        = ["*"]
    path_matcher = "allpaths"
  }
  path_matcher {
    name            = "allpaths"
    default_service = google_compute_backend_bucket.website_backend.self_link
  }
}

# Create HTTPS certificate
resource "google_compute_managed_ssl_certificate" "website_ssl_cert" {
  name        = "website-ssl-cert"
  description = "Managed SSL certificate for the website"
  managed {
    domains = [google_dns_record_set.website_dns.name]
  }
}

# GCP HTTPS Proxy
resource "google_compute_target_https_proxy" "website_https_proxy" {
  name             = "website-https-proxy"
  url_map          = google_compute_url_map.website_url_map.self_link
  ssl_certificates = [google_compute_managed_ssl_certificate.website_ssl_cert.self_link]
}

# GCP HTTP Proxy
resource "google_compute_target_http_proxy" "website_http_proxy" {
  name    = "website-http-proxy"
  url_map = google_compute_url_map.website_url_map.self_link
}

# GCP Forwarding Rule for HTTP
resource "google_compute_global_forwarding_rule" "website_forwarding_rule_http" {
  name                  = "website-forwarding-rule-http"
  load_balancing_scheme = "EXTERNAL"
  ip_address            = google_compute_global_address.website_ip.address
  ip_protocol           = "TCP"
  port_range            = "80"
  target                = google_compute_target_http_proxy.website_http_proxy.self_link
}

# GCP Forwarding Rule for HTTPS
resource "google_compute_global_forwarding_rule" "website_forwarding_rule_https" {
  name                  = "website-forwarding-rule-https"
  load_balancing_scheme = "EXTERNAL"
  ip_address            = google_compute_global_address.website_ip.address
  ip_protocol           = "TCP"
  port_range            = "443"
  target                = google_compute_target_https_proxy.website_https_proxy.self_link
}