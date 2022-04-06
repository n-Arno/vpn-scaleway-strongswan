module "site" {
  source     = "./modules/site"
  count      = 2
  net_prefix = format("%s.%s", "192.168", count.index)
}

