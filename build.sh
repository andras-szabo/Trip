rgbasm main.asm -o main.o
rgblink main.o -o trip.gb -n trip.sym
rgbfix -v -p 0xFF trip.gb
