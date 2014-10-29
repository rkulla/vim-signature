" vim: fdm=marker:et:ts=4:sw=2:sts=2
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
"" Place/Remove/Toggle                                                                                              {{{1
"
function! signature#mark#Toggle(mark)                                                                             " {{{2
  " Description: mark = 'next' : Place new mark on current line else toggle specified mark on current line
  " Arguments:   mark [a-z,A-Z]

  if a:mark == "next"
    " Place new mark
    let l:marks_list = signature#GetMarks('free', 'buf_all')
    if empty(l:marks_list)
      if (!g:SignatureUnconditionallyRecycleMarks)
        " No marks available and mark re-use not in effect
        call s:ReportNoAvailableMarks()
        return
      endif
      " Remove a local mark
      let l:marks_list = signature#GetMarks('used', 'buf_curr')[0]
    endif
    call signature#mark#Move(l:marks_list[0])

  else
    " Toggle Mark
    let l:used_marks = filter(signature#GetMarks('used', 'buf_all'), 'v:val[0] ==# a:mark')
    if ( len(l:used_marks) > 0 )
      let l:mark_pos = l:used_marks[0][1]
      let l:mark_buf = l:used_marks[0][2]

      if (l:mark_buf == bufnr('%'))
        " If the mark is not in use in current buffer then it's a global ==> Don't worry about deleting it
        if (  (l:mark_pos == line('.'))
              \ && !g:SignatureForceMarkPlacement
              \ )
          " Mark is present on the current line. Remove it and return
          call signature#mark#Remove(a:mark)
          return
        else
          " Mark is present elsewhere in the current buffer or g:SignatureForceMarkPlacement is set
          " Remove it but fall-through to place new mark
          " Ask for confirmation before moving mark
          if (g:SignatureDeleteConfirmation)
            let choice = confirm("Mark '" . a:mark . "' has been used elsewhere. Reuse it?", "&Yes\n&No", 1)
            if choice == 2 | return | endif
          endif
          call signature#mark#Remove(a:mark)
        endif
      endif
    endif

    " Place new mark
    call signature#mark#Place(a:mark)
  endif
endfunction


function! signature#mark#Remove(...)                                                                              " {{{2
  " Description: Remove 'mark' and its associated sign. If called without an argument, obtain it from the user
  " Arguments:   a:1 = [a-z,A-Z]

  let l:mark = (a:0 ? a:1 : nr2char(getchar()))
  if stridx(b:SignatureIncludeMarks, l:mark) == -1
    return
  endif

  let l:lnum = line("'" . l:mark)                                                                                 " {{{2
  call signature#ToggleSign(l:mark, "remove", l:lnum)
  execute 'delmarks ' . l:mark
  call signature#mark#ForceGlobalRemoval(l:mark)
endfunction


function! signature#mark#Place(mark)                                                                              " {{{2
  " Description: Place new mark at current cursor position
  " Arguments:   mark = [a-z,A-Z]
  execute 'normal! m' . a:mark
  call signature#ToggleSign( a:mark, "place", line('.'))
endfunction


function! signature#mark#Move(mark)                                                                               " {{{2
  " Description: Move a mark by removing and placing again
  " Arguments:   mark = [a-z,A-Z]
  call signature#mark#Remove(a:mark)
  call signature#mark#Place(a:mark)
endfunction


function! signature#mark#ToggleAtLine()                                                                           " {{{2
  " Description: If no mark on current line, add one. If marks are on the current line, remove one.
  let l:marks_here = filter(signature#GetMarks('used', 'buf_curr'), 'v:val[1] == ' . line('.'))
  if empty(l:marks_here)
    " Set up for adding a mark
    call signature#mark#Toggle('next')
  else
    " Delete first mark
    call signature#mark#Remove(l:marks_here[0][0])
  endif
endfunction


function! signature#mark#Purge(mode)                                                                              " {{{2
  " Description: Delete all marks from current line
  " Arguments:   mode = 'line' : Delete all marks from current line
  "                     'all'  : Delete all marks used in the buffer

  let l:used_marks = signature#GetMarks('used', 'buf_curr')
  if (a:mode ==? 'line')
    call filter(l:used_marks, 'v:val[1] == ' . line('.'))
  endif

  if (  !empty( l:used_marks )
   \ && g:SignaturePurgeConfirmation
   \ )
    let l:msg = 'Are you sure you want to delete all marks' . (a:mode ==? 'line' ? ' from the current line' : '') . '?'
    let l:ans = confirm(l:msg . ' This cannot be undone.', "&Yes\n&No", 1)
    if (l:ans == 2) | return | endif
  endif

  for i in l:used_marks
    call signature#mark#Remove(i[0])
  endfor

  " If there are no marks and markers left, also remove the dummy sign
  if len(b:sig_marks) + len(b:sig_markers) == 0
    call signature#ToggleSignDummy( 'remove' )
  endif
endfunction
" }}}2


""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
"" Navigation                                                                                                       {{{1
"
function! signature#mark#Goto(dir, loc, mode)                                                                     " {{{2
  " Arguments:
  "   dir  = next  : Jump forward
  "          prev  : Jump backward
  "   loc  = line  : Jump to first column of line with mark
  "          spot  : Jump to exact column of the mark
  "   mode = pos   : Jump to next mark by position
  "          alpha : Jump to next mark by alphabetical order

  let l:mark = ""
  let l:dir  = a:dir

  if a:mode ==? "alpha"
    let l:mark = s:GotoByAlpha(a:dir)
  elseif a:mode ==? "pos"
    let l:mark = s:GotoByPos(a:dir)
  endif

  " NOTE: If l:mark is an empty string then no movement will be made
  if l:mark == "" | return | endif

  if a:loc ==? "line"
    execute "normal! '" . l:mark
  elseif a:loc ==? "spot"
    execute 'normal! `' . l:mark
  endif
endfunction


function! s:GotoByPos(dir)                                                                                        " {{{2
  " Description: Jump to next/prev mark by location.
  " Arguments: dir = next : Jump forward
  "                  prev : Jump backward

  " We need at least one mark to be present. If not, then return an empty string so that no movement will be made
  if empty( b:sig_marks ) | return "" | endif

  let l:lnum = line('.')

  " Get list of line numbers of lines with marks.
  if a:dir ==? "next"
    let l:targ = min( sort( keys( b:sig_marks ), "signature#NumericSort" ))
    let l:mark_lnums = sort( keys( filter( copy( b:sig_marks ), 'v:key > l:lnum')), "signature#NumericSort" )
  elseif a:dir ==? "prev"
    let l:targ = max( sort( keys( b:sig_marks ), "signature#NumericSort" ))
    let l:mark_lnums = reverse( sort( keys( filter( copy( b:sig_marks ), 'v:key < l:lnum')), "signature#NumericSort" ))
  endif
  let l:targ = ( empty( l:mark_lnums ) && b:SignatureWrapJumps ? l:targ : l:mark_lnums[0] )
  let l:mark = strpart( b:sig_marks[l:targ], 0, 1 )

  return l:mark
endfunction


function! s:GotoByAlpha(dir)                                                                                      " {{{2
  " Description: Jump to next/prev mark by alphabetical order. Direction specified as input argument

  let l:used_marks = signature#GetMarks('used', 'buf_curr')
  let l:line_marks = filter(copy(l:used_marks), 'v:val[1] == ' . line('.'))

  " If there is only one mark in the current file, then return the same
  if (len(l:used_marks) == 1)
    return l:used_marks[0][0]
  endif

  " Since we can place multiple marks on a line, to jump by alphabetical order we need to know what the current mark is.
  " This information is kept in the b:sig_GotoByAlpha_CurrMark variable. For instance, if we have marks a, b, and c
  " on the current line and b:sig_GotoByAlpha_CurrMark has the value 'a' then we jump to 'b' and set the value of
  " the variable to 'b'. Reinvoking this function will thus now jump to 'c'
  if empty(l:line_marks)
    if exists('b:sig_GotoByAlpha_CurrMark')
      unlet b:sig_GotoByAlpha_CurrMark
    endif
    " If there are no marks present on the current line then call GotoByPos to jump to the next line with a mark
    return s:GotoByPos(a:dir)
  endif

  if (( len(l:line_marks) == 1 ) || !exists('b:sig_GotoByAlpha_CurrMark') || (b:sig_GotoByAlpha_CurrMark ==? ""))
    let b:sig_GotoByAlpha_CurrMark = l:line_marks[0][0]
  endif

  for i in range( 0, len(l:used_marks) - 1 )
    if l:used_marks[i][0] ==# b:sig_GotoByAlpha_CurrMark
      if a:dir ==? "next"
        if (( i != len(l:used_marks)-1 ) || b:SignatureWrapJumps)
          let b:sig_GotoByAlpha_CurrMark = l:used_marks[(i+1)%len(l:used_marks)][0]
        endif
      elseif a:dir ==? "prev"
        if ((i != 0) || b:SignatureWrapJumps)
          let b:sig_GotoByAlpha_CurrMark = l:used_marks[i-1][0]
        endif
      endif
      return b:sig_GotoByAlpha_CurrMark
    endif
  endfor
endfunction
" }}}2


""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
"" Misc                                                                                                             {{{1
"
function! signature#mark#ForceGlobalRemoval(mark)                                                                 " {{{2
  " Description: Edit .viminfo file to forcibly delete Global mark since vim's handling is iffy
  " Arguments:   mark - The mark to delete

  if (  (a:mark !~# '[A-Z]')
   \ || !g:SignatureForceRemoveGlobal
   \ )
    return
  endif

  let l:filename = expand($HOME . '/' . (has('unix') ? '.' : '_') . 'viminfo')
  if (filewritable(l:filename) != 1)
    echohl WarningMsg
    echomsg "Signature: Unable to read/write .viminfo ('" . l:filename . "')"
    echohl None
    return
  endif

  let l:lines = readfile(l:filename, 'b')
  call filter(l:lines, 'v:val !~ "^''' . a:mark. '"')
  if has('win32')
    " for some reason writefile(_viminfo) only works after editing directly
    execute "noautocmd split " . l:filename
    noautocmd write
    noautocmd bdelete
  endif
  call writefile(l:lines, l:filename, 'b')
endfunction


function! s:ReportNoAvailableMarks()                                                                              " {{{2
  if g:SignatureErrorIfNoAvailableMarks
    echoe "Signature: No free marks left."
  else
    echohl WarningMsg
    echomsg "Signature: No free marks left."
    echohl None
  endif
endfunction


function! signature#mark#List(scope)                                                                              " {{{2
  " Description: Opens and populates location list with marks from current buffer
  " Arguments:   scope = buf_curr : List marks from current buffer
  "          ~~~FIXME~~~ buf_all  : List marks from all buffers

  let l:list_map = map(signature#GetMarks('used', a:scope),
                   \   '{
                   \     "bufnr": v:val[2],
                   \     "lnum" : v:val[1],
                   \     "col"  : col("' . "'" . '"  . v:val[0]),
                   \     "type" : "m",
                   \     "text" : v:val[0] . ": " . getline(v:val[1])
                   \   }'
                   \  )

  if (a:scope ==? 'buf_curr')
    call setloclist(0, l:list_map,)|lopen
  "else
  "  call setqflist(l:list_map,)|copen
  endif

  if !exists("g:signature_set_location_list_convenience_maps") || g:signature_set_location_list_convenience_maps
    nnoremap <buffer> <silent> q        :q<CR>
    noremap  <buffer> <silent> <ESC>    :q<CR>
    noremap  <buffer> <silent> <ENTER>  <CR>:lcl<CR>
  endif
endfunction
" }}}2
