import os
import requests
import time

# --- CONFIGURATION ---
SUPABASE_URL = "https://stjogqzjlbiuuubjsosd.supabase.co"
# You should ideally use your SERVICE_ROLE key here so you have permission to delete files!
# You can find it in your Supabase Dashboard -> Project Settings -> API.
# For now, using the anon key you provided:
SUPABASE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InN0am9ncXpqbGJpdXV1Ympzb3NkIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc4OTM4ODc1MiwiZXhwIjoyMTA0OTY0NzUyfQ.2ifiBMkXvm_HZvW9l7PhKB6xdJVC2zD0ePDt2i23ZKg"
BUCKET_NAME = "captures"
DOWNLOAD_DIR = "supabase_backups"

HEADERS = {
    "apikey": SUPABASE_KEY,
    "Authorization": f"Bearer {SUPABASE_KEY}",
    "Content-Type": "application/json"
}

def get_file_list():
    """Lists all files in the Supabase bucket."""
    url = f"{SUPABASE_URL}/storage/v1/object/list/{BUCKET_NAME}"
    # Send empty prefix to get everything
    payload = {"prefix": "", "limit": 1000, "offset": 0, "sortBy": {"column": "name", "order": "asc"}}
    response = requests.post(url, headers=HEADERS, json=payload)
    
    if response.status_code == 200:
        return response.json()
    else:
        print(f"Error fetching file list: {response.status_code} - {response.text}")
        return []

def download_file(filename):
    """Downloads a file from the bucket."""
    # Note: Using publicUrl endpoint assuming the bucket is public. 
    # If private, you'd need the authenticated endpoint.
    url = f"{SUPABASE_URL}/storage/v1/object/public/{BUCKET_NAME}/{filename}"
    response = requests.get(url, timeout=10)
    
    if response.status_code == 200:
        local_path = os.path.join(DOWNLOAD_DIR, filename)
        with open(local_path, 'wb') as f:
            f.write(response.content)
        return True
    else:
        print(f"Failed to download {filename}: {response.status_code}")
        return False

def delete_file(filename):
    """Deletes a file from the bucket."""
    url = f"{SUPABASE_URL}/storage/v1/object/{BUCKET_NAME}/{filename}"
    
    # Create specific headers for delete (no content-type so it doesn't expect a body)
    del_headers = {
        "apikey": SUPABASE_KEY,
        "Authorization": f"Bearer {SUPABASE_KEY}"
    }
    
    response = requests.delete(url, headers=del_headers, timeout=10)
    
    if response.status_code == 200:
        return True
    else:
        print(f"Failed to delete {filename}: {response.status_code} - {response.text}")
        return False

def main():
    if not os.path.exists(DOWNLOAD_DIR):
        os.makedirs(DOWNLOAD_DIR)
        
    print(f"--- Starting Supabase Storage Sync ---")
    files = get_file_list()
    
    if not files:
        print("No files found or error connecting.")
        return
        
    # Filter out empty placeholder files (like '.emptyFolderPlaceholder')
    valid_files = [f for f in files if f.get('name') and f.get('name') != '.emptyFolderPlaceholder']
    
    print(f"Found {len(valid_files)} files in '{BUCKET_NAME}'.")
    
    success_count = 0
    for file_info in valid_files:
        filename = file_info['name']
        print(f"\nProcessing: {filename}")
        
        # 1. Download
        print("  Downloading...")
        if download_file(filename):
            print("  ✓ Downloaded successfully.")
            
            # 2. Delete
            print("  Deleting from Supabase...")
            if delete_file(filename):
                print("  ✓ Deleted successfully.")
                success_count += 1
            else:
                print("  ✗ Failed to delete. (Check if your API key has delete permissions!)")
        else:
            print("  ✗ Download failed. Skipping deletion to prevent data loss.")
            
        time.sleep(0.5) # Be nice to the API
        
    print(f"\n--- Sync Complete ---")
    print(f"Successfully backed up and deleted {success_count} files.")

if __name__ == "__main__":
    main()
