;=====================================================================
; SCLOCK.ACC - Simple Clock 1.0, a menu bar clock desk accessory
; for the Atari ST, TOS 1.04. Created by Rick Grinstead.
;
; Shows the GEMDOS system time as a 12-hour clock ("h:MMpm" or
; "h:MM:SSpm") in the upper right corner of the GEM menu bar, with an
; optional beep at the top of each hour. Select "Simple Clock" in the
; Desk menu to change the settings.
;
; Assemble (vasm, Motorola syntax, Devpac compatible):
;   vasmm68k_mot -Ftos -devpac -nosym -o SCLOCK.ACC SCLOCK.S
; Devpac 2/3 should also assemble it unchanged (output as .ACC).
;
; Install: copy SCLOCK.ACC to the root of the boot drive and reboot.
;=====================================================================

MU_MESAG        equ     $0010
MU_TIMER        equ     $0020
AC_OPEN         equ     40
WF_WORKXYWH     equ     4
BEG_UPDATE      equ     1
END_UPDATE      equ     0
M_OFF           equ     256
M_ON            equ     257
TICK_MIN_MS     equ     1000            ; poll interval, h:mm mode
TICK_SEC_MS     equ     100             ; poll interval, h:mm:ss mode
SEC_REFRESH     equ     10              ; forced redraw every 10 ticks
MOUSE_MARGIN    equ     16              ; cursor size, for hide test
MAX_LEN         equ     10              ; " 1:07:45pm"
_hz_200         equ     $4ba            ; 200 Hz system tick counter

MODE_OFF        equ     0
MODE_MIN        equ     1
MODE_SEC        equ     2

        text

;---------------------------------------------------------------------
; Entry. For an accessory TOS passes the basepage in a0 and the
; memory is already sized, so there is no Mshrink; just set a stack.
;---------------------------------------------------------------------
start:
        lea     stack_top,sp

        ; ap_id = appl_init()
        lea     c_appl_init,a0
        bsr     aes
        move.w  int_out,ap_id

        ; menu_id = menu_register(ap_id, "  Simple Clock")
        move.w  ap_id,int_in
        move.l  #acc_name,addr_in
        lea     c_menu_register,a0
        bsr     aes
        move.w  int_out,menu_id

        ; physical workstation handle and system character size
        lea     c_graf_handle,a0
        bsr     aes
        move.w  int_out,vdi_handle
        move.w  int_out+2,char_w
        move.w  int_out+4,char_h

        ; v_opnvwk(): intin[0..9] = 1, intin[10] = 2 (raster coords)
        lea     vintin,a0
        moveq   #9,d0
.fill:  move.w  #1,(a0)+
        dbra    d0,.fill
        move.w  #2,(a0)
        moveq   #100,d0
        moveq   #0,d1
        moveq   #11,d2
        bsr     vdi
        move.w  vcontrl+12,vdi_handle
        move.w  vintout,d3              ; d3 = screen xmax

        ; vswr_mode(REPLACE): text cells overwrite the background
        move.w  #1,vintin
        moveq   #32,d0
        moveq   #0,d1
        moveq   #1,d2
        bsr     vdi
        ; vst_color(BLACK)
        move.w  #1,vintin
        moveq   #22,d0
        moveq   #0,d1
        moveq   #1,d2
        bsr     vdi
        ; vst_alignment(left, top) so y is the top of the cell
        clr.w   vintin
        move.w  #5,vintin+2
        moveq   #39,d0
        moveq   #0,d1
        moveq   #2,d2
        bsr     vdi

        ; menu bar height = y of the desktop work area
        clr.w   int_in                  ; window 0 = desktop
        move.w  #WF_WORKXYWH,int_in+2
        lea     c_wind_get,a0
        bsr     aes
        move.w  int_out+4,desk_y

        ; clock_right = xmax + 1 - char_w  (one character margin);
        ; text is right-aligned against it
        addq.w  #1,d3
        sub.w   char_w,d3
        move.w  d3,clock_right

        ; clock_y = (desk_y - 1 - char_h) / 2, centred above the line
        move.w  desk_y,d0
        subq.w  #1,d0
        sub.w   char_h,d0
        asr.w   #1,d0
        bpl.s   .y_ok
        moveq   #0,d0
.y_ok:  move.w  d0,clock_y

        bsr     get_time                ; no beep for the hour we start in
        move.w  d0,last_hour

;---------------------------------------------------------------------
; Main loop: wait for a message or the timer.
;---------------------------------------------------------------------
loop:
        lea     int_in,a0
        moveq   #15,d0
.clr:   clr.w   (a0)+
        dbra    d0,.clr
        move.w  #MU_MESAG|MU_TIMER,int_in
        move.w  #TICK_MIN_MS,d0
        cmp.w   #MODE_SEC,mode
        bne.s   .slow
        move.w  #TICK_SEC_MS,d0
.slow:  move.w  d0,int_in+28            ; timer low word
        move.l  #msgbuf,addr_in
        lea     c_evnt_multi,a0
        bsr     aes
        move.w  int_out,d7              ; events that happened

        btst    #4,d7                   ; MU_MESAG?
        beq.s   .no_msg
        cmp.w   #AC_OPEN,msgbuf
        bne.s   .no_msg
        move.w  msgbuf+8,d0             ; msg[4] = menu id
        cmp.w   menu_id,d0
        bne.s   .no_msg
        bsr     on_open
.no_msg:
        btst    #5,d7                   ; MU_TIMER?
        beq     loop

        ; hourly beep: minute 0 of an hour we have not beeped for yet
        tst.w   beep_on
        beq.s   .no_beep
        bsr     get_time
        tst.w   d2
        bne.s   .no_beep
        cmp.w   last_hour,d0
        beq.s   .no_beep
        move.w  d0,last_hour
        bsr     beep
.no_beep:
        tst.w   mode
        beq     loop
        bsr     tick_clock
        bra     loop

;---------------------------------------------------------------------
; Desk menu entry chosen. Clock cycles Off -> h:mm -> h:mm:ss -> Off,
; Beep toggles the hourly beep; both show the box again. Done closes.
;---------------------------------------------------------------------
on_open:
        bsr     update_status
        move.w  #3,int_in               ; default button = Done
        move.l  #alert_text,addr_in
        lea     c_form_alert,a0
        bsr     aes
        move.w  int_out,d0
        cmp.w   #1,d0
        beq.s   .clock
        cmp.w   #2,d0
        beq.s   .beep
        rts                             ; Done
.beep:  eor.w   #1,beep_on
        bra.s   on_open
.clock: lea     blank_text,a3           ; erase the widest clock
        moveq   #MAX_LEN,d5
        bsr     draw_text
        move.w  mode,d0
        addq.w  #1,d0
        cmp.w   #MODE_SEC,d0
        bls.s   .set
        moveq   #MODE_OFF,d0
.set:   move.w  #-1,last_2s             ; resynchronise the seconds
        move.w  d0,mode
        beq.s   on_open                 ; now off: nothing to draw
        clr.w   redraw_cnt              ; force an immediate draw
        bsr     tick_clock
        bra.s   on_open

;---------------------------------------------------------------------
; Write the current settings into the alert's status line.
;---------------------------------------------------------------------
update_status:
        lea     st_clock,a0
        move.w  mode,d0
        mulu    #7,d0
        lea     mode_names,a1
        add.w   d0,a1
        moveq   #6,d0
.cp:    move.b  (a1)+,(a0)+
        dbra    d0,.cp
        lea     st_beep,a0
        tst.w   beep_on
        beq.s   .off
        move.b  #'O',(a0)+
        move.b  #'N',(a0)+
        move.b  #' ',(a0)
        rts
.off:   move.b  #'O',(a0)+
        move.b  #'F',(a0)+
        move.b  #'F',(a0)
        rts

;---------------------------------------------------------------------
; Ring the console bell: Bconout(CON, 7).
;---------------------------------------------------------------------
beep:   move.w  #7,-(sp)
        move.w  #2,-(sp)
        move.w  #3,-(sp)
        trap    #13
        addq.l  #6,sp
        rts

;---------------------------------------------------------------------
; Read the clock: d0 = hours (0-23), d2 = minutes, d3 = seconds.
;
; GEMDOS only stores seconds in 2-second steps. The odd second is
; filled in from the 200 Hz counter: we note _hz_200 when the 2-second
; value changes, and add 1 once 200 ticks (1 s) have passed since.
;---------------------------------------------------------------------
get_time:
        bsr     read_hz
        move.l  d0,d4                   ; d4 = _hz_200 now
        move.w  #$2C,-(sp)              ; Tgettime()
        trap    #1
        addq.l  #2,sp
        ; d0 = hhhhh mmmmmm sssss (seconds / 2)
        move.w  d0,d3
        and.w   #31,d3                  ; d3 = seconds / 2
        move.w  d0,d2
        lsr.w   #5,d2
        and.w   #63,d2                  ; d2 = minutes
        moveq   #11,d1
        lsr.w   d1,d0
        and.w   #31,d0                  ; d0 = hours

        move.w  last_2s,d1
        cmp.w   d3,d1
        beq.s   .same
        move.w  d3,last_2s              ; 2-second value changed
        move.l  d4,mark_hz
        clr.w   synced
        cmp.w   #-1,d1                  ; first reading: phase unknown
        beq.s   .same
        move.w  #1,synced
.same:  add.w   d3,d3                   ; even seconds
        tst.w   synced
        beq.s   .done
        move.l  d4,d1
        sub.l   mark_hz,d1              ; ticks since the change
        cmp.l   #200,d1
        blt.s   .done
        cmp.l   #400,d1                 ; stale (we were not running)
        bge.s   .stale
        addq.w  #1,d3                   ; odd second
.done:  rts
.stale: clr.w   synced
        rts

; d0 = _hz_200, read in supervisor mode via Supexec()
read_hz:
        pea     get_hz(pc)
        move.w  #38,-(sp)               ; Supexec
        trap    #14
        addq.l  #6,sp
        rts
get_hz: move.l  _hz_200.w,d0
        rts

;---------------------------------------------------------------------
; Build the time string and draw it if it changed (or the forced
; refresh is due, which repairs it if a menu bar was redrawn over it).
;---------------------------------------------------------------------
tick_clock:
        bsr     build_time              ; time_text, d5 = length
        subq.w  #1,redraw_cnt
        ble.s   .draw
        lea     time_text,a0
        lea     last_text,a1
        moveq   #MAX_LEN-1,d0
.cmp:   cmpm.b  (a0)+,(a1)+
        dbne    d0,.cmp
        bne.s   .draw
        rts
.draw:  moveq   #1,d0                   ; h:mm mode: every tick (1 s)
        cmp.w   #MODE_SEC,mode
        bne.s   .reload
        moveq   #SEC_REFRESH,d0         ; h:mm:ss: every 10 ticks (1 s)
.reload:
        move.w  d0,redraw_cnt
        lea     time_text,a0
        lea     last_text,a1
        moveq   #MAX_LEN-1,d0
.copy:  move.b  (a0)+,(a1)+
        dbra    d0,.copy
        lea     time_text,a3
        bra     draw_text

;---------------------------------------------------------------------
; Build " h:MMam", " h:MM:SSam" etc. in time_text; d5 = length.
;---------------------------------------------------------------------
build_time:
        bsr     get_time
        ; 24 h -> 12 h: 0 -> 12 am, 1-11 am, 12 pm, 13-23 -> 1-11 pm
        moveq   #'a',d4
        cmp.w   #12,d0
        blo.s   .am
        moveq   #'p',d4
        sub.w   #12,d0
.am:    tst.w   d0
        bne.s   .h_ok
        moveq   #12,d0
.h_ok:
        lea     time_text,a3
        move.w  d0,d1
        bsr     two_digits
        cmp.b   #'0',time_text          ; " 9:45" not "09:45"
        bne.s   .no_pad
        move.b  #' ',time_text
.no_pad:
        move.b  #':',(a3)+
        move.w  d2,d1
        bsr     two_digits
        moveq   #7,d5
        cmp.w   #MODE_SEC,mode
        bne.s   .no_sec
        move.b  #':',(a3)+
        move.w  d3,d1
        bsr     two_digits
        moveq   #MAX_LEN,d5
.no_sec:
        move.b  d4,(a3)+                ; 'a' or 'p'
        move.b  #'m',(a3)+
        rts

;---------------------------------------------------------------------
; Draw the d5-character string at a3, right-aligned to clock_right.
;---------------------------------------------------------------------
draw_text:
        move.w  d5,d0
        mulu    char_w,d0
        move.w  clock_right,d4
        sub.w   d0,d4                   ; d4 = x

        ; wind_update(BEG_UPDATE) - waits while a menu is dropped down
        move.w  #BEG_UPDATE,int_in
        lea     c_wind_update,a0
        bsr     aes

        ; hide the mouse only if it is near the clock (no flicker)
        moveq   #0,d6
        lea     c_graf_mkstate,a0
        bsr     aes
        move.w  d4,d0
        sub.w   #MOUSE_MARGIN,d0
        cmp.w   int_out+2,d0            ; mouse x < x - margin?
        bgt.s   .draw
        move.w  desk_y,d0
        add.w   #MOUSE_MARGIN,d0
        cmp.w   int_out+4,d0            ; mouse y >= desk_y + margin?
        ble.s   .draw
        move.w  #M_OFF,int_in
        clr.l   addr_in
        lea     c_graf_mouse,a0
        bsr     aes
        moveq   #1,d6

.draw:  ; v_gtext(handle, x, y, string)
        lea     vintin,a0
        move.w  d5,d0
        subq.w  #1,d0
.copy:  moveq   #0,d1
        move.b  (a3)+,d1
        move.w  d1,(a0)+
        dbra    d0,.copy
        move.w  d4,vptsin
        move.w  clock_y,vptsin+2
        moveq   #8,d0
        moveq   #1,d1
        move.w  d5,d2
        bsr     vdi

        tst.w   d6
        beq.s   .end
        move.w  #M_ON,int_in
        clr.l   addr_in
        lea     c_graf_mouse,a0
        bsr     aes
.end:   move.w  #END_UPDATE,int_in
        lea     c_wind_update,a0
        bra     aes                     ; tail call

;---------------------------------------------------------------------
; d1.w (0-99) -> two ASCII digits at (a3)+
;---------------------------------------------------------------------
two_digits:
        and.l   #$ffff,d1
        divu    #10,d1
        add.b   #'0',d1
        move.b  d1,(a3)+
        swap    d1
        add.b   #'0',d1
        move.b  d1,(a3)+
        rts

;---------------------------------------------------------------------
; AES call. a0 -> 5 control words. Trashes d0-d2/a0-a2.
;---------------------------------------------------------------------
aes:    lea     control,a1
        move.l  (a0)+,(a1)+
        move.l  (a0)+,(a1)+
        move.w  (a0),(a1)
        move.l  #aespb,d1
        move.w  #200,d0
        trap    #2
        rts

;---------------------------------------------------------------------
; VDI call. d0 = opcode, d1 = ptsin count, d2 = intin count.
;---------------------------------------------------------------------
vdi:    lea     vcontrl,a0
        move.w  d0,(a0)
        move.w  d1,2(a0)
        move.w  d2,6(a0)
        move.w  vdi_handle,12(a0)
        move.l  #vdipb,d1
        move.w  #115,d0
        trap    #2
        rts

;=====================================================================
        data
;=====================================================================
; AES control arrays: opcode, #int_in, #int_out, #addr_in, #addr_out
c_appl_init:     dc.w    10,0,1,0,0
c_evnt_multi:    dc.w    25,16,7,1,0
c_menu_register: dc.w    35,1,1,1,0
c_form_alert:    dc.w    52,1,1,1,0
c_graf_handle:   dc.w    77,0,5,0,0
c_graf_mouse:    dc.w    78,1,1,1,0
c_graf_mkstate:  dc.w    79,0,5,0,0
c_wind_get:      dc.w    104,2,5,0,0
c_wind_update:   dc.w    107,1,1,0,0

aespb:  dc.l    control,global,int_in,int_out,addr_in,addr_out
vdipb:  dc.l    vcontrl,vintin,vptsin,vintout,vptsout

mode:           dc.w    MODE_MIN        ; clock on, no seconds, at boot
beep_on:        dc.w    0               ; hourly beep off at boot
last_2s:        dc.w    -1
redraw_cnt:     dc.w    0

acc_name:       dc.b    "  Simple Clock",0
alert_text:     dc.b    "[0][Simple Clock 1.0|Created by Rick Grinstead |"
                dc.b    "Shows the GEMDOS time|in the menu bar.|"
                dc.b    "Clock: "
st_clock:       dc.b    "h:mm   "
                dc.b    "  Beep: "
st_beep:        dc.b    "OFF"
                dc.b    "][Clock|Beep|Done]",0
mode_names:     dc.b    "OFF    h:mm   h:mm:ss"
blank_text:     dc.b    "          "
        even

;=====================================================================
        bss
;=====================================================================
control:        ds.w    5
global:         ds.w    15
int_in:         ds.w    16
int_out:        ds.w    7
addr_in:        ds.l    3
addr_out:       ds.l    1

vcontrl:        ds.w    12
vintin:         ds.w    32
vptsin:         ds.w    8
vintout:        ds.w    64
vptsout:        ds.w    16

msgbuf:         ds.w    8
ap_id:          ds.w    1
menu_id:        ds.w    1
vdi_handle:     ds.w    1
char_w:         ds.w    1
char_h:         ds.w    1
desk_y:         ds.w    1
clock_right:    ds.w    1
clock_y:        ds.w    1
last_hour:      ds.w    1
synced:         ds.w    1
mark_hz:        ds.l    1
time_text:      ds.b    MAX_LEN
last_text:      ds.b    MAX_LEN
        even

                ds.l    256             ; 1 KB stack
stack_top:
