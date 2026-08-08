# Explicit Free Tier–oriented settings (pass with: terraform apply -var-file=free-tier.tfvars)
# Eligible accounts: ~750 hrs/mo t3.micro|t2.micro, ~30 GB EBS, 5 GB S3 — see current AWS Free Tier terms.

instance_type      = "t3.micro"
root_volume_gb     = 30
ollama_model       = "llama3.2:1b"
ollama_embed_model = "nomic-embed-text"
force_destroy_buckets = true
