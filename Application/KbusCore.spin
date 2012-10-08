 ''********************************************
''*  K-Bus Tranceiver 1.5                    *
''*  Author: Nick McClanahan (c) 2012        *
''*  See end of file for terms of use.       *
''********************************************

{-----------------REVISION HISTORY-----------------                     
r1.5
* Added experimental dbus routines
* removed notification LED settings

r1.4 (W/ Kracker 0.59)
* Improved nextcode timeout
* made multicore friendly
* Fixed RxTxPad bug.  New default is  much longer  

r1.2 (W/ Kracker 0.57):
* Improved RX/TX performance and faster nextcode

r1.1 (W/ Kracker 0.56):
* RxTxPad now sets waittime when shifting from RX to TX
* Added Stop Bit Check
* Improvements to Holdforcode

r1.0 (With Kracker 0.55):                                                        CIRCUIT:                       
  Sync'ed Serial TX object with additonal features for iBus                              3.3v                   
                                                                                                               
Changes from Kracker 0.54:                                                            10k                      
* Complete rewrite, K-bus functions are now bundled with Serial IO              RXPIN ───┻──┳──── Ibus Data 
* Stateless RX                                                                                 │                
                                                                                TXPIN ─────  ┌─ Ibus Gnd  
                                                                                           10k │  │             
                                                                                                              
                                                                         Use method Start(27rxpin, 26txpin, %0110, 9600)
}                                                                       
                                                                        
CON                                                                     
_clkmode = xtal1 + pll16x                               
_xinfreq = 5_000_000                                    

bufsiz = 128 '16       'buffer size (16, 32, 64, 128, 256, 512) must be factor of 2, max is 512 
bufmsk = bufsiz - 1    'buffer mask used for wrap-around ($00F, $01F, $03F, $07F, $0FF, $1FF)   
bitsiz = 9         
'bitsiz = 8 + 1 + 1     '8 bits + parity + stop   (not coded for 8,0,1 so don't change!!)
 
RxTxPad = 8000    'Padding betwen RX and TX period - this is how long (prev 8000) 
                 ' About 20 clocks for each decrement; 1 ms = 4000 
                                                              '
KbusCog = 6
radsize = 11

VAR
  long  cog               'cog flag/id
  '9 contiguous longs:
  long  rx_head       'Start addr of data still in the rx buffer
  long  rx_tail       'End addr of data in the rx buffer
  long  tx_head
  long  tx_tail
  long  rx_pin
  long  tx_pin
  long  rxtx_mode
  long  bit_ticks
  long  buffer_ptr
                     
  byte  rx_buffer[bufsiz]           'transmit and receive buffers
  byte  tx_buffer[bufsiz]

  byte  coderef[40]
  byte  codein[80]    'Storage for successfully received code.  Does not flush
  BYTE  RADstring[32] 'Use to build strings for the RAD display
  byte  outcodeprep[40] 
  byte  codelock      ' Track status of received code
  byte  xmitlock      ' Track the status of trasmit services

  
PUB start(rxpin, txpin, mode, baudrate) : okay

  stop
  longfill(@rx_head, 0, 4)
  longmove(@rx_pin, @rxpin, 3)
  bit_ticks := clkfreq / baudrate
  buffer_ptr := @rx_buffer
  coginit(kbuscog, @entry, @rx_head)
  okay := kbuscog



''Instructions added specifically for the KBus
PUB codeptr
''Returns a pointer to the codein string
return @codein

PUB sendtext(strptr)   | strlen
''Sends a text string to the RAD
strlen := strsize(strptr) <# radsize

BYTEFILL(@radstring, 0, 32)
radstring[0] := $C8
radstring[1] := 5 + strlen
radstring[2] := $80
radstring[3] := $23 
radstring[4] := $42
radstring[5] := $32                            

bytemove(@radstring+6, strptr, strlen)
sendcode(@radstring)


PUB sendnav(strptr, pos)
''Sends a text string to the NAV at pos,                    

BYTEFILL(@radstring, 0, 32)
radstring[0] := $F0 
radstring[1] := 6 + strsize(strptr)
radstring[2] := $3B
radstring[3] := $A5
radstring[4] := $62 
radstring[5] := $01
radstring[6] := pos

bytemove(@radstring+7, strptr, strsize(strptr))
sendcode(@radstring)





PRI RXislocked
IF lockset(codelock)
  return TRUE
ELSE
  return FALSE

PRI UnlockRX
lockclr(codelock)
return TRUE


PUB codecompare(cptr1) | i, codelen
''Compare the code at cptr1 with the code in codein
   
codelen :=  byte[cptr1][1]
 
IF codelen
  repeat i from 0 to codelen
    if byte[cptr1 + i] <> codein[i]
      return FALSE

return TRUE

PUB clearcode

IF NOT Rxislocked
  bytefill(@codein, 0, 40)
  return unlockRX


PUB codestored

IF NOT Rxislocked
  IF @codein[1] <> 0
    return unlockRX
  ELSE
    return !unlockRX
return FALSE



PUB dbus(outcode, ms) | holdtime, len, i, checksum, codelen
'12 04 00 16
i := 0
repeat until NOT lockset(xmitlock)

checksum := 0
codelen := byte[outcode+1] <#  80

repeat i from 0 to codelen - 2
  tx(byte[outcode+i])
  checksum ^= byte[outcode+i]
tx(checksum)
lockclr(xmitlock)

{  
repeat until RXislocked

holdtime := ms * 80000  #> 400000  
ctrb := %00110_000 << 23 + 31 << 9 + 31 'Establish mode duty
frqb := 1
phsb~

I := 0
repeat
  If phsb > holdtime
    bytefill(@codein, 0, 40)
    return !unlockRX

  if rxcount < 2
    next
  codein[i++] := rx
  codein[i] := rx
  len := codein[i++] - 2
  repeat len
    codein[i++] := rx
  unlockRX
  return @codein
}  
 
PUB nextcode(ms) | checksum, len, holdtime, base, i, blocking
''Next code tests every byte in the RX buffer until it finds a valid message
''That message is stored in Codein
''Call with 0 ms to make blocking

IF RXislocked
  return FALSE

dira[0]~
ctrb := %00110_000 << 23 + 0 << 9 + 0 'Establish mode duty
frqb := 1
phsb~

base := rx_tail
checksum :=0


holdtime := ms * 80000  #> 400000

repeat
  IF ms > 0
    If phsb > holdtime
      bytefill(@codein, 0, 40)
      return !unlockRX                                                                                                                 
     
  IF rxcount < 5           
    next

  len := getrx(1, base)         'Get the length, verify it's possible  
  IF (len == 0) OR (len > 32)                                                                     
    rxtime(2)
    base++
    next

  If rxcount < len + 2
    next  
 
  repeat i from 0 to len             'Calc checksum
    checksum ^= getrx(i, base)

  IF checksum == getrx(Len + 1, base)
    repeat i from 0 to len + 1
      codein[i] := rxtime(2)
    return unlockRX   

  ELSE
    rxtime(2)  
    base++  
    checksum := 0

                       
PRI getrx(depth, starttail)
'' Gets a byte in the rx buffer, [depth] bytes deep starting at [starttail]
return rx_buffer[(starttail+depth) & bufmsk]

PUB partialmatch(match, length) | i
''Determine if the code at codein matches the pattern at match
''Match format: $80, $00, $FF, $24, $01
''Use bytes where you want a matching byte, and $00 where the value might change
'' [length] is how far down the code to test for a match

  
repeat i from 0 to length - 1
  if (BYTE[match][i] <> codein[i]) AND (BYTE[match][i] <> 0)
    Return FALSE    

return TRUE 



PUB sendcode(outcode) | i, codelen, checksum
''Send the code stored as Hex at the location given by codeptr, Checksum is automatically calculated
repeat until NOT lockset(xmitlock)

checksum := 0
codelen := byte[outcode+1] <#  32

repeat i from 0 to codelen
  outcodeprep[i] := byte[outcode+i]
  checksum ^= outcodeprep[i]
outcodeprep[codelen + 1] := checksum

repeat i from 0 to codelen + 1
  tx(outcodeprep[i])
lockclr(xmitlock)
  


PUB IgnitionStatus : ignstat
''PASSIVE - you'll need to compare every incoming code with this method
''to see if it containts the Ignition status.  -1 means no update 
if partialmatch(@IgnitionCode, 4) 
  ignstat := codein[4]
else
  ignstat:= -1  


PUB OutTemp :Temp | i
''PASSIVE - you'll need to compare every incoming code with this method
'' -1 = no update
if partialmatch(@tempcode, 4)
  Temp := (codein[4] * 9 / 5) + 32
else
  temp:= -1     


PUB CoolTemp :Temp | i
''PASSIVE - you'll need to compare every incoming code with this method
'' -1 = no update

if partialmatch(@tempcode, 4) 
  Temp := (codein[5] * 9 / 5) + 32
else
  temp:= -1   


PUB RPMs :RPM | i
''PASSIVE - you'll need to compare every incoming code with this method
'' -1 = no update
if partialmatch(@RPMCode, 4)
  RPM := codein[5] * 100
else
  rpm := -1    


PUB Speed :mph | i
''PASSIVE - you'll need to compare every incoming code with this method
'' -1 = no update.  This field is updated by the KMB every second

if partialmatch(@RPMCode, 4)
  mph := (codein[4] * 5 / 8) / 2
else
  mph := -1


PUB Odometer :miles | i
''ACTIVE - this method queries the KMB and returns the result

sendcode(@OdometerReq)
repeat 5
  NextCode(50)
  if partialmatch(@OdometerResp, 4)
    BYTE[@miles][2] :=  codein[6]
    BYTE[@miles][1] :=  codein[5]
    BYTE[@miles][0] :=  codein[4]
    Miles := (Miles * 5 /8 )
    RETURN miles
  ELSE
    miles := -1


PUB localtime(strptr)   | i
''ACTIVE - this method queries the KMB and writes the result
''to [strptr].  0 Terminated string

Repeat until NOT lockset(codelock) 
UnlockRX

sendcode(@timeReq)
repeat 3
   nextcode(50)   
   if partialmatch(@timeResp, 5)
      BYTEMOVE(strptr, @codein+6, 7)
      BYTE[strptr][7] :=  0
      return TRUE
   ELSE
      Byte[strptr] := 0

return FALSE




PUB fuelAverage(strptr) | i
''ACTIVE - this method queries the KMB and writes the result
''to [strptr].  0 Terminated string

sendcode(@fuelReq) 
repeat 5
  nextcode(50)                         
  if partialmatch(@fuelResp, 5) 
    i := Byte[@codein+1]  - 5
    BYTEMOVE(strptr, @codein+6, i)
    BYTE[strptr][i+1] :=  0
    return TRUE
  ELSE
    Byte[strptr] := 0
RETURN FALSE
    


PUB EstRange(strptr) | i
''ACTIVE - this method queries the KMB and writes the result
''to [strptr].  0 Terminated string

sendcode(@rangeReq) 
repeat 5
  nextcode(50)
  if partialmatch(@rangeResp, 5) 
    i := Byte[@codein+1]  - 5
    BYTEMOVE(strptr, @codein+6, i)
    BYTE[strptr][i+1] :=  0
    RETURN TRUE
  ELSE
    Byte[strptr] := 0

RETURN FALSE

PUB Date(strptr) | i
''ACTIVE - this method queries the KMB and writes the result
''to [strptr].  0 Terminated string

sendcode(@dateReq) 
repeat 5
  nextcode(50)
  if partialmatch(@dateResp, 5)
    i := Byte[@codein+1]  - 5
    BYTEMOVE(strptr, @codein+6, i)
    BYTE[strptr][i+1] :=  0
    RETURN TRUE
  ELSE
    Byte[strptr] := 0
RETURN FALSE   




PUB RxCount : count
{{Get count of characters in receive buffer.
  Returns: number of characters waiting in receive buffer.}}

  count := rx_head - rx_tail
  count -= bufsiz*(count < 0)



PUB stop
' Stop serial driver - frees a cog

  cogstop(KbusCog)
  longfill(@rx_head, 0, 9)

PUB rxflush
'' Flush receive buffer

  repeat while rxcheck => 0
  
PUB rxavail : truefalse
'' Check if byte(s) available
'' returns true (-1) if bytes available

  truefalse := rx_tail <> rx_head

PUB txcheck : truefalse
'' Check if byte(s) in tx buffer
'' returns true (-1) if bytes available

  truefalse := tx_tail <> tx_head

PUB rxcheck : rxbyte

'' Check if byte received (never waits)
'' returns -1 if no byte received, $00..$FF if byte

  rxbyte--
  if rx_tail <> rx_head
    rxbyte := rx_buffer[rx_tail]
    rx_tail := (rx_tail + 1) & bufmsk


PUB rxtime(ms) : rxbyte | t

'' Wait ms milliseconds for a byte to be received
'' returns -1 if no byte received, $00..$FF if byte

  t := cnt
  repeat until (rxbyte := rxcheck) => 0 or (cnt - t) / (clkfreq / 1000) > ms
  

PUB rx : rxbyte

'' Receive byte (may wait for byte)
'' returns $00..$FF

  repeat while (rxbyte := rxcheck) < 0


PUB tx(txbyte)

'' Send byte (may wait for room in buffer)

  repeat until (tx_tail <> (tx_head + 1) & bufmsk)
  tx_buffer[tx_head] := txbyte
  tx_head := (tx_head + 1) & bufmsk

  if rxtx_mode & %1000
    rx


DAT                 

'***********************************
'* Assembly language serial driver *
'***********************************

                        org     0
'
'
' Entry
'
entry                   mov     t1,par                'get structure address
                        add     t1,#4 << 2            'skip past heads and tails

                        rdlong  t2,t1                 'get rx_pin
                        mov     rxmask,#1
                        shl     rxmask,t2

                        add     t1,#4                 'get tx_pin
                        rdlong  t2,t1
                        mov     txmask,#1
                        shl     txmask,t2

                        add     t1,#4                 'get rxtx_mode
                        rdlong  rxtxmode,t1

                        add     t1,#4                 'get bit_ticks
                        rdlong  bitticks,t1

                        add     t1,#4                 'get buffer_ptr
                        rdlong  rxbuff,t1
                        mov     txbuff,rxbuff
                        add     txbuff,#bufsiz

                        or      dira,txmask
                        mov     txcode,#transmit
                        

receive                 jmpret  rxcode,txcode         'run a chunk of transmit code, then return


                        test    rxmask,ina      wc     '
         if_c           jmp     #receive           'We switch to Transmit by jumping to Receive
 
                        mov     mbit, zero                           
                        mov     rxbits,#bitsiz        'ready to receive byte


                        mov     rxcnt, cnt      
                        add     rxcnt,bitticks        'ready next bit period
                        waitcnt rxcnt, #0

                        'Now in the begining of the first bit


:bit                    add     rxcnt, bitticks       'setup read for next bit

:midbitsample           test    rxmask,ina      wc    'receive bit on rx pin
               IF_c     adds     mbit, #1
               IF_nc    subs     mbit, #1     
                        cmp      rxcnt, cnt     wc ' write C when RXcnt is less than cnt
               IF_nc    jmp     #:midbitsample     
                        cmps    zero, mbit       wc  'write c when mbit is less than 0
                        rcr     rxdata,#1
                        mov     mbit, zero

                        djnz    rxbits,#:bit

                          
                         shr     rxdata,#32-9
'                        shr     rxdata,#32-bitsiz     'justify and trim received byte (ignore checking parity!)



                        and     rxdata,#$FF
                        test    rxtxmode,#%001  wz    'if rx inverted, invert byte
        if_nz           xor     rxdata,#$FF

                        rdlong  t2,par                'save received byte and inc head
                        add     t2,rxbuff
                        wrbyte  rxdata,t2
                        sub     t2,rxbuff
                        add     t2,#1
                        and     t2,#bufmsk
                        wrlong  t2,par

                        mov     txwait, txwaittimer   'Set TX waittimer             
                        jmp     #transmit              'byte done, receive next byte


transmit                jmpret  txcode,rxcode         'run a chunk of receive code, then return

                        djnz    txwait, #Transmit  WZ
              IF_Z      mov     txwait, #1 

                        mov     t1,par                'check for head <> tail
                        add     t1,#2 << 2
                        rdlong  t2,t1
                        add     t1,#1 << 2
                        rdlong  t3,t1
                        cmp     t2,t3           wz                                                                                                     
        if_z            jmp     #transmit               'Nothing to send, switch to Receive               '          CIRCUIT:                           
                                                                                                          '                  3.3v                       
                                                                                                          '                                            
                                                                                                          '               10k                          
                        add     t3,txbuff             'get byte and inc tail                               '        RXPIN ───┻──┳──── Ibus Data     
                        rdbyte  txdata,t3                                                                  '                       │                    
                        sub     t3,txbuff                                                                  '        TXPIN ─────  ┌─ Ibus Gnd      
                        add     t3,#1                                                                      '                   22k │  │                 
                        and     t3,#bufmsk                                                                 '                                          
                        wrlong  t3,t1

                        test    txdata,#$FF     wc    'set parity bit (note parity forced!!)
        if_c            or      txdata,#$100          'if parity odd, make even
                        or      txdata,stopbit        'add stop bit  
''                        or      txdata,#$100        'ready byte to transmit
                        shl     txdata,#2
                        or      txdata,#1
                        mov     txbits,#bitsiz+2
                        mov     txcnt,cnt
                        add     txcnt,bitticks        'ready next cnt
                        
:bit                    test    rxtxmode,#%100  wz    'Write Z if NOT open collector  (test writes Z if a AND b == 0)
                        test    rxtxmode,#%010  wc
        if_z_and_c      xor     txdata,#1
                        shr     txdata,#1       wc
        if_z            muxc    outa,txmask           'NOT open collecter?  Set output      
        if_z            muxc    dira,txmask           'NOT open collecter?  Set output
    

                        
                        waitcnt txcnt, bitticks

                        djnz    txbits,#:bit          'another bit to transmit?
        if_z            andn    outa,txmask
        if_z            andn    dira,txmask
        
                        jmp     #receive             'byte done, Check for next byte to Transmit




'txled                   long    1 << LEDtx
mbit                    long    0
zero                    long    0
'msgled                  long    1 << LEDMsg          
'bittimer                long    1 << LEDBitClock     
'rxLED                   long    1 << LEDRx           

txwait                  long  1
txwaittimer             long  RxTxPad



stopbit                 long    $200                 'when parity used
stopcheck               LONG     1 << 9


'DATA for kbus RX/TX
TempCode        BYTE $80, $00, $BF, $19                                                           
RPMCode         BYTE $80, $00, $BF, $18


'Message Templates;
{
$80 $05 $BF $10 $10 $00 
             -- --      
              |  | 
              |  |---- RPM $10 * $A0 ($10 * 100.0 
              |   
              |------- Speed = $10 * 2 kph 



}



IgnitionCode    BYTE $80, $00, $BF, $11                                                           
                                                                                                  
                                                                                                  
OdometerReq     BYTE $44, $03, $80, $16                                                           
OdometerResp    BYTE $80, $00, $BF, $17                                                           
                                                                                                  
                                                                                                  
timeReq         BYTE $3B, $05, $80, $41, $01, $01                                                 
timeResp        BYTE $80, $00, $FF, $24, $01                                                      
                                                                                                  
dateReq         BYTE $3B, $05, $80, $41, $02, $01                                                 
dateResp        BYTE $80, $00, $FF, $24, $02                                                      
                                                                                                  
fuelReq         BYTE $3B, $05, $80, $41, $04, $01                                                 
fuelResp        BYTE $80, $00, $FF, $24, $04                                                      
                                                                                                  
rangeReq        BYTE $3B, $05, $80, $41, $06, $01                                                 
rangeResp       BYTE $80, $00, $FF, $24, $06      




  


' Uninitialized data
'
t1                      res     1
t2                      res     1
t3                      res     1

rxtxmode                res     1
bitticks                res     1

rxmask                  res     1
rxbuff                  res     1
rxdata                  res     1
rxbits                  res     1
rxcnt                   res     1
rxcode                  res     1

txmask                  res     1
txbuff                  res     1
txdata                  res     1
txbits                  res     1
txcnt                   res     1
txcode                  res     1

{{

┌──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                                   TERMS OF USE: MIT License                                                  │                                                            
├──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation    │ 
│files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy,    │
│modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software│
│is furnished to do so, subject to the following conditions:                                                                   │
│                                                                                                                              │
│The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.│
│                                                                                                                              │
│THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE          │
│WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR         │
│COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,   │
│ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                         │
└──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
}}