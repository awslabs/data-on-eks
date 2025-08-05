# Descripton des modules déployés



## Général
La liste des modules déployés ont été modifiés pour être compatible avec EKS Outpost.
Les compatibilités liés à l'outpost sont disponible [ici](https://docs.aws.amazon.com/outposts/latest/userguide/instance-types.html#instance-types-available-in-outposts).
Pour résumé sur les modifications effectués lié à la compatibilité avec EKS Outpost :
-   Les instances EC2 utilisées pour les nœuds de calcul sont des instances disponibles dans l'outpost.
-   Le volume EBS utilisé ont été modifié pour utiliser du volume type gp2 car gp3 n'est pas compatible dans l'outpost. 
-   Les BDD instancié sont des postgresql RDS dans l'outpost.
- 
## Déploiement du cluster EKS
TODO

## Airflow on EKS with RDS and S3 Sync Sidecar


Airflow a été mis en place dans eks avec une base de données RDS utilisant un volume EBS de AWS. La base de données RDS est instancié avec un postgresql.
Le blueprint a été modifié pour permettre de récupérer les fichiers dans S3 AWS par les pods airflow via l'ajout d'un sidecar dans les pods airflow.
Le sidecar permet de faire un S3 sync pour récupérer les fichiers dag dans le pod airflow.
Sans ce mécanisme mis en place, les fichiers dag ne seraient pas visible.

Note : Par défaut le blueprint utilise EFS de AWS. Celui ci n'est pas disponible dans outpost.
Note2 : Le S3 que l'on utilise est celui en dehors de outpost.
Note 3 : la BDD est créé dans le outpost avec une instance BDD disponible dans l'outpost. 
Note 4 : Airflow est déployé dans le namespace airflow et permet de créer des traitements dans le namespace airflow.

Les tests réalisés : insertion dans S3 et traitement par airflow d'un fichier dag simple et un autre qui utilise KubernetesPodOperator sur le namespace airflow

Pour le moment la sécurisation de l'application se fait encore via login et mot de passe (admin/admin).

## Trino on EKS 

Trino a été mis en place dans eks avec un connecteur iceberg et un metastore postgresql en rds.
Le connecteur iceberg permet de faire des requêtes sur des données stockées dans S3 AWS.

Keda et Karpenter sont configurés pour fonctionner ensemble, permettant à Keda de gérer l'auto-scaling des pods Trino en fonction des métriques de charge de travail et à Karpenter de provisionner dynamiquement les nœuds nécessaires dans le cluster EKS.
Le prometheus manager et le metrics server sont ajoutés pour permettre à Keda de s'appuyer sur les métriques.

Les tests réalisés : 
-   on utilise des exemples du blueprint pour injecter des données via la cli trino
-   on utilise des exemples du blueprint pour requeter des données via la cli trino

## Tips

Suppression du lock si besoin : 

```
aws dynamodb delete-item --table-name tf-backend-012046422670 --key '{"LockID": {"S": "tf-backend-012046422670/terraform/state-poc-olt4"}}'
```