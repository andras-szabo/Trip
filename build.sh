rgbasm main.asm -o main.o
rgblink main.o -o trip.gb
rgbfix -v -p 0xFF trip.gb
