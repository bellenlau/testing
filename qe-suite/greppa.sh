grep -l "All done. ERROR:" * | while read f; do
    echo "================================================================================" >> errors_extracted.txt
    echo "FILE: $f" >> errors_extracted.txt
    echo "================================================================================" >> errors_extracted.txt

    # Cerca e stampa eventuale riga FAILED
    echo "FAILED lines:" >> errors_extracted.txt
    grep "FAILED" "$f" >> errors_extracted.txt || echo "No FAILED line found" >> errors_extracted.txt

    echo "" >> errors_extracted.txt

    # Estrai errori
    grep -A999999 "All done. ERROR:" "$f" >> errors_extracted.txt

    echo -e "\n" >> errors_extracted.txt
done
