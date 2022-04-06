output "access_gws" {
  value = zipmap(module.site.*.subnet, module.site.*.ssh)
}

