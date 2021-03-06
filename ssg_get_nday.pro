;+
; $Id: ssg_get_nday.pro,v 1.6 2015/03/04 15:53:44 jpmorgen Exp $

; ssg_get_nday 
;
; Reads nday from FITS header, if it exists, otherwise generates one
; from FITS header values.  If REGENERATE specified or nday has not
; been recorded in hdr before, modifies DATE-OBS keyword to be Y2K
; compliant and inserts NDAY keyword into header.
;
; Calls ssg_exceptions
;
; DEFINITION OF NDAY.  Rawjd is derived above from UT time and date of
; _start_ of exposure.  Nday is going to be related to the Julian day
; at the _midpoint_ of the exposure.
;
; Julian date would be a fine reference, but they are a bit large at
; this point (start at noon, GMT, 1/1/4713 BC), so define our own
; system, before which none of our observations were recorded.
; Someone has beat us to this idea, by making reduced Julian day,
; which is the output of some handy ASTROLIB functions.  Reduced
; Julian days start at noon on 11/16/1858 (JD=2400000), which is still
; a little large for us at this point.

; So, Let's define our nday=0 to be 1/1/1990 00:00UT = JD 2447892.5,
; since all our observations occur within a few hours from 0UT.

; Note, julian days begin at noon.  Also, IDL julday, though handy as
; a function, returns real Julian Day.  ASTROLIB's juldate returns
; reduced Julian day, which is JD-2400000, or Julian day starting from
; 11/16/1858

; Newer files:
; DATE-OBS= '2002-03-17T01:42:42'  /  Y2K compliant (yyyy-mm-ddThh:mm:ss)
; UT      = '01:42:42          '  /  universal time (start of
; exposure)
;
; Older files:
; DATE-OBS= '14/07/94          '  /  date (dd/mm/yy) of obs.
; UT      = '06:24:16.00       '  /  universal time

;-
function ssg_get_nday, hdr, REGENERATE=regenerate, formatted=formatted

  init = {ssg_sysvar}

  nday = 0.D
  ;; If we are not regenerating, do a quick header read
  if NOT keyword_set(regenerate) then begin
     nday = sxpar(hdr, 'NDAY', count=count)
     if count gt 0 then begin
        formatted = string(format='(f11.5)', nday)
        return, nday
     endif
  endif

  sxaddhist, string('(ssg_get_nday.pro) ', systime(/UTC), ' UT'), hdr
  ;; Starting in 1998, DATE-NEW was added to the header as a Y2K
  ;; transition measure.  
  newdate = strtrim(sxpar(hdr,'DATE-NEW',COUNT=count))
  if count ne 0 then begin
     rawdate_obs = strtrim(sxpar(hdr,'DATE-OBS',COUNT=count))
     if count eq 1 then begin
        sxaddhist, string('(ssg_get_nday.pro) copying DATE-NEW to DATE-OBS'), hdr
        sxaddpar, hdr, 'ODATEOBS', rawdate_obs, 'Old DATE-OBS'
        sxaddpar, hdr, 'DATE-OBS', newdate, 'Y2K compliant (yyyy-mm-ddThh:mm:ss)'
     endif
  endif
  rawdate_obs = strtrim(sxpar(hdr,'DATE-OBS',COUNT=count))
  ;; Just in case HEASARC conventions of _ instead of - are being followed
  if count eq 0 then begin
     rawdate_obs = sxpar(hdr,'DATE_OBS',COUNT=count)
     sxaddpar, hdr, 'DATE-OBS', rawdate_obs, 'added for consistency with other SSG data'
  endif

  raw_ut = strtrim(sxpar(hdr,'UT',COUNT=count),2)

  datearr=strsplit(rawdate_obs,'-T:',/extract)
  if N_elements(datearr) ne 6 then begin
     ;; Old date format, DD/MM/YY
     datearr=strsplit(rawdate_obs,'/',/extract)
     if N_elements(datearr) ne 3 then $
       message, /CONTINUE, 'WARNING: malformed DATE-OBS or DATE_OBS keyword'
     timearr=strsplit(raw_ut,':',/extract)
     if N_elements(timearr) ne 3 then $
       message, /CONTINUE, 'WARNING: malformed UT keyword'
     year_fits = fix(datearr[2])
     ;; The study started in 1990
     if year_fits ge 90 then $
       year_fits = year_fits+1900 $
     else $
       year_fits = year_fits+2000
     year_fits = string(year_fits)
     month_fits = fix(datearr[1])
     day_fits = datearr[0]
     
     ;; Put a leading 0 on the month
     if month_fits lt 10 then begin
        month_fits = string(format='("0", i1)', month_fits)
     endif else begin
        month_fits = strtrim(string(month_fits),2)
     endelse
     
     rawdate_obs = year_fits + '-' + month_fits + '-' + day_fits + 'T' + raw_ut
     rawdate_obs = strtrim(rawdate_obs,2)
     sxaddpar, hdr, 'DATE-OBS', rawdate_obs, 'Y2K compliant (yyyy-mm-ddThh:mm:ss)'
  endif
  ;; New Y2K convention
  datearr=strsplit(rawdate_obs,'-T:',/extract)
  temp=strsplit(strtrim(rawdate_obs),'T',/extract)
  if NOT strcmp(temp[1], raw_ut) then $
       message, /CONTINUE, 'WARNING: DATE-OBS and UT times do not agree, using DATE-OBS version'

  ;; juldate returns reduced Julian Day
  juldate, double(datearr), rawjd
  rawjd = rawjd + !eph.jd_reduced

  darktime = sxpar(hdr, 'DARKTIME',COUNT=count)
  if count eq 0 then begin
     message, /CONTINUE, 'WARNING: DARKTIME keyword not found: unlikely to be an SSG image'
     darktime = sxpar(hdr, 'EXPTIME')
     if count eq 0 then begin
        message, /CONTINUE, 'WARNING: EXPTIME keyword not found: unlikely to be an SSG image.  Using begining of the exposure for nday reference'
        darktime = 0
     endif
  endif

  nday = rawjd + (darktime/2.d)/3600.d/24.d - !ssg.JDnday0
  sxaddpar, hdr, 'NDAY', nday, 'Decimal days of obs. midpoint since 1990-1-1T12:00:00 UT'

  ;; ssg_exceptions should not modify nday, since that is what
  ;; ssg_fix_head is for
  ;;ssg_exceptions, im, hdr
  nday = sxpar(hdr, 'NDAY')
  formatted = string(format='(f11.5)', nday)

  return, nday


end
