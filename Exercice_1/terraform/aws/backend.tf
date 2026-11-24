# State local, déclaré explicitement (aucun backend distant dans ce projet)
terraform {
  backend "local" {
    path = "terraform.tfstate"
  }
}
