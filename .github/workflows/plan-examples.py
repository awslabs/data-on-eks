import json
import glob
import re


def get_examples():
    """
    Get all Terraform example root directories using their respective `versions.tf`;
    returning a string formatted json array of the example directories minus those that are excluded
    """
    exclude = {
        'ai-ml/ray/terraform', # Skip until we fix CI script to test as per v5 convention
        'ai-ml/ray/terraform/examples/pytorch', # Example relies on cluster created by parent blueprint
        'ai-ml/ray/terraform/examples/xgboost', # Example relies on cluster created by parent blueprint
        'ai-ml/jupyterhub', # Requires a domain name
        'analytics/terraform/datahub-on-eks/datahub-addon', # Internal module, covered under root example and not standalone
        'streaming/nifi', # Requires a domain name
    }

    projects = {
        x.replace('/versions.tf', '')
        for x in glob.glob('**/**/**/versions.tf', recursive=True)
        if not re.match(r'.*(modules|workshop).*', x)
    }

    print(json.dumps(list(projects.difference(exclude))))


if __name__ == '__main__':
    get_examples()
