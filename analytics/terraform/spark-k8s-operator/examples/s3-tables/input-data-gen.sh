#!/bin/bash

# Variables
output_file="employee_data.csv"
num_records=100

# Levels array
levels=("Junior" "Mid" "Senior" "Exec")

# Create or overwrite the CSV file with the header
echo "id,name,level,salary" > $output_file

# Generate data
for ((i=1; i<=num_records; i++))
do
    # Generate random name
    name="Employee_$i"

    # Pick a random level
    level=${levels[$RANDOM % ${#levels[@]}]}

    # Generate a random salary between 50,000 and 200,000
    salary=$(echo "scale=2; $RANDOM/32768 * (200000 - 50000) + 50000" | bc)

    # Append the data to the CSV file
    echo "$i,$name,$level,$salary" >> $output_file
done

# Print a success message
echo "Generated $num_records employee records in $output_file"
