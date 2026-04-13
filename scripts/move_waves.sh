#!/bin/sh

echo Converting waves: *.{vcd,wlf,fst}

find . -name "*.wlf" -print0 | while IFS= read -r -d '' file; do
    echo "Converting $file..."
    wlf2vcd "$file" -o "${file%.wlf}.vcd"
done

find . -name '*.vcd' -print0 | while IFS= read -r -d '' file; do
    echo "$file -> ../../../sim/${file%.vcd}.fst"
    vcd2fst -v "$file" -f "${file%.vcd}.fst"
    mv "${file%.vcd}.fst" "../../../sim/${file%.vcd}.fst"
done


#rm -f *.vcd *.wlf