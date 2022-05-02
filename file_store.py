import os

size_limit_in_GB = 0

def delete_files(delete_all=False):
    # Function to delete least recently accessed cache files when size limit exceeded
    # As an example, a race dataset is ~200MB
    folder_size = 0
    file_modified_dict = {}
    directory = "./file_system_store/"
    deleted_file_count = 0
    for file in os.listdir(directory):
        file_size = os.path.getsize(directory + file)
        folder_size += file_size
        file_modified_dict[os.path.getatime(directory + file)] = (file, file_size)

    folder_size_in_GB = folder_size / 1000000000

    if folder_size_in_GB > size_limit_in_GB and delete_all == False:
        
        sorted_files = sorted(file_modified_dict.items())
        while folder_size_in_GB > size_limit_in_GB and len(sorted_files) > 0:
            record = sorted_files[0]
            file = record[1][0]
            size = record[1][1]
            folder_size_in_GB -= size / 1000000000
            os.remove(directory + file)
            sorted_files.pop(0)
            deleted_file_count += 1

        return deleted_file_count

    if delete_all == True:
        for key in file_modified_dict:
            file = file_modified_dict[key][0]
            os.remove(directory + file)

    return None


def cleanup():
    # Function to be called periodically to delete cache files over a given age
    pass


