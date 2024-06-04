import boto3
import time
from botocore.exceptions import NoCredentialsError, PartialCredentialsError

def get_bucket_size(bucket_name):
    s3 = boto3.client('s3')
    total_size = 0
    try:
        paginator = s3.get_paginator('list_objects_v2')
        for page in paginator.paginate(Bucket=bucket_name):
            for obj in page.get('Contents', []):
                total_size += obj['Size']
    except NoCredentialsError:
        print("Credentials not available.")
        return None
    except PartialCredentialsError:
        print("Incomplete credentials provided.")
        return None
    except Exception as e:
        print(f"An error occurred: {e}")
        return None

    return total_size

def format_size_mb(size):
    # Convert size to MB
    return size / (1024 * 1024)

def delete_directory(bucket_name, prefix):
    s3 = boto3.client('s3')
    try:
        paginator = s3.get_paginator('list_objects_v2')
        for page in paginator.paginate(Bucket=bucket_name, Prefix=prefix):
            delete_objects = [{'Key': obj['Key']} for obj in page.get('Contents', [])]
            if delete_objects:
                s3.delete_objects(Bucket=bucket_name, Delete={'Objects': delete_objects})
        print(f"Successfully deleted directory '{prefix}' in bucket '{bucket_name}'.")
    except NoCredentialsError:
        print("Credentials not available.")
    except PartialCredentialsError:
        print("Incomplete credentials provided.")
    except Exception as e:
        print(f"An error occurred while deleting the directory: {e}")

def main():
    bucket_name = input("Enter the S3 bucket name: ")
    refresh_interval = 10  # Refresh interval in seconds

    while True:
        action = input("Enter 'size' to get bucket size or 'delete' to delete a directory: ").strip().lower()
        if action == 'size':
            size = get_bucket_size(bucket_name)
            if size is not None:
                size_mb = format_size_mb(size)
                print(f"Total size of bucket '{bucket_name}': {size_mb:.2f} MB")
            else:
                print(f"Failed to get the size of bucket '{bucket_name}'.")
        elif action == 'delete':
            prefix = input("Enter the directory prefix to delete (e.g., 'myfolder/'): ").strip()
            delete_directory(bucket_name, prefix)
        else:
            print("Invalid action. Please enter 'size' or 'delete'.")

        time.sleep(refresh_interval)

if __name__ == "__main__":
    main()
