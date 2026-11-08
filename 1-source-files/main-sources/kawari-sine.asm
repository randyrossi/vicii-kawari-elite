; SNE sine table for the co-processor planet job (as in elite-data.asm).

.pl_SNE
 FOR I%, 0, 31
  N = ABS(SIN((I% / 64) * 2 * PI))
  IF N >= 1
   EQUB 255
  ELSE
   EQUB INT(256 * N + 0.5)
  ENDIF
 NEXT
