variable "overlayfolder" {
  type        = string
  description = "Repertoire d'overlay a resoudre"
}

variable "helminstallname" {
  type        = string
  description = "Nom de l'installation helm"
}

variable "namespace" {
  type        = string
  description = "Namespace cible de l'installation"
}

variable "createnamespace" {
  type        = bool
  description = "Le répertoire doit il etre créé ?"
  default     = false
}