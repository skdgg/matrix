## Generate test cases (run in sim/)
### Vertex processing
* Fixed 3 vertex
```
python3 gen_vtx.py --mode fixed3 --outdir test_vertex  
```
* Random vertex
```
python3 gen_vtx.py --mode random --n 256 --seed 0 --outdir test_vertex
```

## Run simulation
* Matrix Vector Multiplication
```
make rtl0 [FSDB=2]
```
* Vertex Processing
```
make rtl1 TOL=X [FSDB=2]
```
X can be 0 or 1, it can tolerance a little mismatch if TOL=1


