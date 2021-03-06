program test

  use FoX_wkml

  implicit none

  type(xmlf_t) :: myfile
  type(color_t) :: mycolor

  call kmlSetCustomColor(mycolor, 'F90000FF')

  call kmlBeginFile(myfile, "test.xml", -1)
  call kmlCreatePolygonStyle(myfile, id='myid', colorhex='f90000ff', outline=.true.)
  call kmlFinishFile(myfile)

end program test
