module m_sax_fsm

  use FoX_common, only: dictionary_t, add_key_to_dict, add_value_to_dict, &
       init_dict, reset_dict, destroy_dict
  use m_common_array_str, only: vs_str, str_vs
  use m_common_buffer, only: buffer_t, buffer_to_chararray, len, str, &
       buffer_nearly_full, add_to_buffer, reset_buffer
  use m_common_error, only: FoX_warning, FoX_error
  use m_common_elstack, only: elstack_t, init_elstack, reset_elstack, destroy_elstack
  use m_common_charset, only: validchars, initialnamechars, namechars, &
       whitespace, uppercase, operator(.in.)
  
  use m_sax_entities, only: init_entity_list, destroy_entity_list, reset_entity_list
  use m_sax_entities, only: entity_list, entity_filter_text_len, entity_filter_text
  use m_sax_entities, only: is_unparsed_entity
  use m_sax_namespaces, only: namespaceDictionary, initNamespaceDictionary, &
       destroyNamespaceDictionary
  
  implicit none
  private

  type, public :: fsm_t
    ! Contains information about the "finite state machine"
    integer                          :: state
    integer                          :: context
    integer                          :: nbrackets
    integer                          :: nlts
    character(len=1)                 :: quote_char
    type(buffer_t)                   :: buffer
    character, dimension(:), pointer :: element_name
    type(dictionary_t)               :: attributes
    type(namespaceDictionary)        :: nsDict
    character, dimension(:), pointer :: pcdata
    logical                          :: entities_in_pcdata
    logical                          :: entities_in_attributes
    type(elstack_t)                  :: element_stack
    logical                          :: root_element_seen
    character, dimension(:), pointer :: root_element_name
    type(entity_list)                :: entities
    character(len=150)               :: action
    logical                          :: debug
    logical                          :: xml_decl_ok
  end type fsm_t

  public :: init_fsm, reset_fsm, destroy_fsm, evolve_fsm

  ! State parameters
  integer, parameter, public   ::  ERROR = -1
  integer, parameter, public   ::  INIT = 1         
  integer, parameter, private  ::  START_TAG_MARKER = 2
  integer, parameter, private  ::  END_TAG_MARKER = 3
  integer, parameter, private  ::  IN_NAME = 4
  integer, parameter, private  ::  WHITESPACE_IN_TAG = 5
  integer, parameter, private  ::  IN_PCDATA = 6
  integer, parameter, private  ::  SINGLETAG_MARKER = 7
  integer, parameter, private  ::  CLOSINGTAG_MARKER = 8
  integer, parameter, private  ::  IN_COMMENT = 9
  integer, parameter, private  ::  IN_ATT_NAME = 10
  integer, parameter, private  ::  IN_ATT_VALUE = 11
  integer, parameter, private  ::  EQUAL = 12
  integer, parameter, private  ::  SPACE_AFTER_EQUAL = 13
  integer, parameter, private  ::  SPACE_BEFORE_EQUAL = 14
  integer, parameter, private  ::  START_QUOTE = 15
  integer, parameter, private  ::  END_QUOTE = 16
  integer, parameter, private  ::  BANG = 17
  integer, parameter, private  ::  BANG_HYPHEN = 18
  integer, parameter, private  ::  ONE_HYPHEN = 19
  integer, parameter, private  ::  TWO_HYPHEN = 20
  integer, parameter, private  ::  START_PI = 22
  integer, parameter, private  ::  IN_DTD = 23
  integer, parameter, private  ::  IN_CDATA_SECTION = 24
  integer, parameter, private  ::  ONE_BRACKET = 25
  integer, parameter, private  ::  TWO_BRACKET = 26
  integer, parameter, private  ::  CDATA_PREAMBLE = 27
  integer, parameter, private  ::  IN_PI_TARGET = 28
  integer, parameter, private  ::  IN_PI_WHITESPACE = 29
  integer, parameter, private  ::  IN_PI_CONTENT = 30
  integer, parameter, private  ::  IN_PCDATA_AT_EOL = 31
  integer, parameter, private  ::  QUESTION_MARK_IN_TARGET = 32
  integer, parameter, private  ::  QUESTION_MARK_IN_CONTENT = 33

  ! Context parameters
  integer, parameter, public   ::  OPENING_TAG  = 100
  integer, parameter, public   ::  CLOSING_TAG  = 110
  integer, parameter, public   ::  SINGLE_TAG   = 120
  integer, parameter, public   ::  COMMENT_TAG  = 130
  integer, parameter, public   ::  PI_TAG  = 140
  integer, parameter, public   ::  DTD_TAG  = 150
  integer, parameter, public   ::  CDATA_SECTION_TAG  = 160
  integer, parameter, public   ::  NULL_CONTEXT          = 200

  ! Signal parameters
  integer, parameter, public   ::  QUIET             = 1000
  integer, parameter, public   ::  END_OF_TAG        = 1100
  integer, parameter, public   ::  CHUNK_OF_PCDATA   = 1200
  integer, parameter, public   ::  EXCEPTION         = 1500
  
contains

!------------------------------------------------------------
! Initialize once and for all the derived types (Fortran90 restriction)
!
subroutine init_fsm(fx) 
type(fsm_t), intent(inout)   :: fx

 fx%state = INIT
 fx%context = NULL_CONTEXT
 call init_elstack(fx%element_stack)
 fx%root_element_seen = .false.
 fx%debug = .false.
 fx%entities_in_pcdata = .false.
 fx%entities_in_attributes = .false.
 fx%action = ""
 call reset_buffer(fx%buffer)
 nullify(fx%element_name)
 nullify(fx%pcdata)
 nullify(fx%root_element_name)
 call init_dict(fx%attributes)
 call initNamespaceDictionary(fx%nsDict)
 call init_entity_list(fx%entities, PE=.false.)
 fx%xml_decl_ok = .true.
end subroutine init_fsm
!------------------------------------------------------------
subroutine reset_fsm(fx) 
type(fsm_t), intent(inout)   :: fx

 fx%state = INIT
 fx%context = NULL_CONTEXT
 call reset_elstack(fx%element_stack)
 fx%action = ""
 fx%root_element_seen = .false.
 call reset_buffer(fx%buffer)
 if (associated(fx%element_name)) deallocate(fx%element_name)
 nullify(fx%element_name)
 if (associated(fx%pcdata)) deallocate(fx%pcdata)
 nullify(fx%pcdata)
 if (associated(fx%root_element_name)) deallocate(fx%root_element_name)
 nullify(fx%root_element_name)
 call reset_dict(fx%attributes)
 call destroyNamespaceDictionary(fx%nsDict)
 call initNamespaceDictionary(fx%nsDict)
 call reset_entity_list(fx%entities)
 fx%xml_decl_ok = .true.
end subroutine reset_fsm

subroutine destroy_fsm(fx) 
type(fsm_t), intent(inout)   :: fx

 fx%state = INIT
 fx%context = NULL_CONTEXT
 call destroy_elstack(fx%element_stack)
 fx%action = ""
 fx%root_element_seen = .false.
 call reset_buffer(fx%buffer)
 if (associated(fx%element_name)) deallocate(fx%element_name)
 if (associated(fx%pcdata)) deallocate(fx%pcdata)
 if (associated(fx%root_element_name)) deallocate(fx%root_element_name)
 call destroy_dict(fx%attributes)
 call destroyNamespaceDictionary(fx%nsDict)
 call destroy_entity_list(fx%entities)
end subroutine destroy_fsm

!------------------------------------------------------------
subroutine evolve_fsm(fx,c,signal)
!
! Finite-state machine evolution rules for XML parsing.
!
type(fsm_t), intent(inout)      :: fx    ! Internal state
character(len=1), intent(in)    :: c
integer, intent(out)            :: signal

! Reset signal
!
signal = QUIET

! Reset pcdata
if (associated(fx%pcdata)) deallocate(fx%pcdata)

if (.not. (c .in. validchars)) then
!
!      Let it pass (in case the underlying encoding is UTF-8)
!      But this chars in a name will cause havoc
!
!      signal = EXCEPTION
!      fx%state = ERROR
!      fx%action = trim("Not a valid character in simple encoding: "//c)
!      RETURN
endif

select case(fx%state)

 case (INIT)
      if (c == "<") then
         fx%state = START_TAG_MARKER
         if (fx%debug) fx%action = ("Starting tag")
      else if (c.in.whitespace) then
         fx%xml_decl_ok = .false.
       else
         fx%state = ERROR
         if (fx%debug) fx%action = ("Reading garbage chars")
      endif

 case (START_TAG_MARKER)
      if (c == ">") then
         fx%state = ERROR
         fx%action = ("Tag empty!")
      else if (c == "<") then
         fx%state = ERROR
         fx%action = ("Double opening of tag!!")
      else if (c == "/") then
         fx%state = CLOSINGTAG_MARKER
         if (fx%debug) fx%action = ("Starting endtag: ")
         fx%context = CLOSING_TAG
      else if (c == "?") then
         fx%state = START_PI
         if (fx%debug) fx%action = ("Starting PI ")
         fx%context = PI_TAG
      else if (c == "!") then
         fx%state = BANG
         if (fx%debug) fx%action = ("Saw ! -- comment or DTD expected...")
      else if (c .in. whitespace) then
         fx%state = ERROR
         fx%action = ("Cannot have whitespace after <")
      else if (c .in. initialNameChars) then
         fx%context = OPENING_TAG
         fx%state = IN_NAME
         call reset_buffer(fx%buffer)
         call add_to_buffer(c,fx%buffer)
         if (fx%debug) fx%action = ("Starting to read name in tag")
      else 
         fx%state = ERROR
         fx%action = ("Illegal initial character for name")
      endif

      ! if we are at the start, preserve that info ...
      if (fx%xml_decl_ok) fx%xml_decl_ok = (fx%state == START_PI)


 case (BANG)
      if (c == "-") then
         fx%state = BANG_HYPHEN
         if (fx%debug) fx%action = ("Almost ready to start comment ")
      else if (c .in. uppercase) then
         if (fx%root_element_seen) then
           fx%state = ERROR
           fx%action = "DTD found after root element"
         else
           fx%state = IN_DTD
           fx%nlts = 0
           fx%nbrackets = 0
           if (fx%debug) fx%action = ("DTD declaration ")
           fx%context = DTD_TAG
           call add_to_buffer(c,fx%buffer)
         endif
      else if (c == "[") then
         fx%state = CDATA_PREAMBLE
         if (fx%debug) fx%action = ("Declaration with [ ")
         fx%context = CDATA_SECTION_TAG
      else
         fx%state = ERROR
         fx%action = ("Wrong character after ! ")
      endif

      

 case (CDATA_PREAMBLE)
      ! We assume a CDATA[ is forthcoming, we do not check
      if (c == "[") then
         fx%state = IN_CDATA_SECTION
         if (fx%debug) fx%action = ("About to start reading CDATA contents")
      else if (c == "]") then
         fx%state = ERROR
         fx%action = ("Unexpected ] in CDATA preamble")
      else
         if (fx%debug) fx%action = ("Reading CDATA preamble")
      endif

 case (IN_CDATA_SECTION)
      if (c == "]") then
         fx%state = ONE_BRACKET
         if (fx%debug) fx%action = ("Saw a ] in CDATA section")
      else
         call add_to_buffer(c,fx%buffer)
         if (fx%debug) fx%action = ("Reading contents of CDATA section")
      endif

 case (ONE_BRACKET)
      if (c == "]") then
         fx%state = TWO_BRACKET
         if (fx%debug) fx%action = ("Maybe finish a CDATA section")
      else
         fx%state = IN_CDATA_SECTION
         call add_to_buffer("]",fx%buffer)
         if (fx%debug) fx%action = ("Continue reading contents of CDATA section")
      endif

 case (TWO_BRACKET)
      if (c == ">") then
         fx%state = END_TAG_MARKER
         signal = END_OF_TAG
         if (fx%debug) fx%action = ("End of CDATA section")
         allocate(fx%pcdata(len(fx%buffer)))
         fx%pcdata = buffer_to_chararray(fx%buffer)
                ! Not quite the same behavior
                ! as pcdata... (not filtered)
         call reset_buffer(fx%buffer)
      else
         fx%state = IN_CDATA_SECTION
         call add_to_buffer("]",fx%buffer)
         if (fx%debug) fx%action = ("Continue reading contents of CDATA section")
      endif

 case (IN_DTD)
      if (c == "<") then
         fx%nlts = fx%nlts + 1
         call add_to_buffer("<",fx%buffer)
         fx%action = "Read an intermediate < in DTD"
      else if (c == "[") then
         fx%nbrackets = fx%nbrackets + 1
         call add_to_buffer("[",fx%buffer)
         fx%action = "Read a [ in DTD"
      else if (c == "]") then
         fx%nbrackets = fx%nbrackets - 1
         call add_to_buffer("]",fx%buffer)
         fx%action = "Read a ] in DTD"
      else if (c == ">") then
         if (fx%nbrackets == 0) then
           fx%state = END_TAG_MARKER
           signal  = END_OF_TAG
           if (fx%debug) fx%action = ("Ending DTD")
           allocate(fx%pcdata(len(fx%buffer)))
           fx%pcdata = buffer_to_chararray(fx%buffer)
                  ! Same behavior as pcdata
           call reset_buffer(fx%buffer)
         else
            fx%nlts = fx%nlts -1
            call add_to_buffer(">",fx%buffer)
            fx%action = "Read an intermediate > in DTD declaration"
         endif
      else
         if (fx%debug) fx%action = ("Keep reading DTD")
         call add_to_buffer(c,fx%buffer)
      endif

 case (BANG_HYPHEN)
      if (c == "-") then
         fx%state = IN_COMMENT
         fx%context = COMMENT_TAG
         if (fx%debug) fx%action = ("In comment ")
      else
         fx%state = ERROR
         fx%action = ("Wrong character after <!- ")
      endif

 case (START_PI)
      if (c .in. initialNameChars) then
         fx%state = IN_PI_TARGET
         call reset_buffer(fx%buffer)
         call add_to_buffer(c,fx%buffer)
         if (fx%debug) fx%action = ("Starting to read name in PI")
      else
         fx%state = ERROR
         fx%action = "Wrong initial character for PI target"
      endif

 case (CLOSINGTAG_MARKER)
      if (c == ">") then
         fx%state = ERROR
         fx%action = ("Closing tag empty!")
      else if (c == "<") then
         fx%state = ERROR
         fx%action = ("Double opening of closing tag!!")
      else if (c == "/") then
         fx%state = ERROR
         fx%action = ("Syntax error (<//)")
      else if (c .in. whitespace) then
         fx%state = ERROR
         fx%action = ("Cannot have whitespace after </")
      else if (c .in. initialNameChars) then
         fx%state = IN_NAME
         if (fx%debug) fx%action = ("Starting to read name inside endtag")
         call add_to_buffer(c,fx%buffer)
      else 
         fx%state = ERROR
         fx%action = ("Illegal initial character for name")
      endif

 case (IN_NAME)
      if (c == "<") then
         fx%state = ERROR
         fx%action = ("Starting tag within tag")
      else if (c == ">") then
         fx%state = END_TAG_MARKER
         signal  = END_OF_TAG
         if (fx%debug) fx%action = ("Ending tag")
if (associated(fx%element_name)) deallocate(fx%element_name)
         allocate(fx%element_name(len(fx%buffer)))
         fx%element_name = buffer_to_chararray(fx%buffer)
         call reset_buffer(fx%buffer)
         call reset_dict(fx%attributes)
      else if (c == "/") then
         if (fx%context /= OPENING_TAG) then
            fx%state = ERROR
            fx%action = ("Single tag did not open as start tag")
         else 
            fx%state = SINGLETAG_MARKER
            fx%context = SINGLE_TAG
            if (fx%debug) fx%action = ("Almost ending single tag")
if (associated(fx%element_name)) deallocate(fx%element_name)
            allocate(fx%element_name(len(fx%buffer)))
            fx%element_name = buffer_to_chararray(fx%buffer)
            call reset_buffer(fx%buffer)
            call reset_dict(fx%attributes)
         endif
      else if (c .in. whitespace) then
         fx%state = WHITESPACE_IN_TAG
         if (fx%debug) fx%action = ("Ending name chars")
if (associated(fx%element_name)) deallocate(fx%element_name)
         allocate(fx%element_name(len(fx%buffer)))
         fx%element_name = buffer_to_chararray(fx%buffer)
         call reset_buffer(fx%buffer)
         call reset_dict(fx%attributes)
      else if (c .in. NameChars) then
         if (fx%debug) fx%action = ("Reading name chars in tag")
         call add_to_buffer(c,fx%buffer)
      else
         fx%state = ERROR
         fx%action = ("Illegal character for name")
      endif

 case (IN_ATT_NAME)
      if (c == "<") then
         fx%state = ERROR
         fx%action = ("Starting tag within tag")
      else if (c == ">") then
         fx%state = ERROR
         fx%action = ("Ending tag in the middle of an attribute")
      else if (c == "/") then
         fx%state = ERROR
         fx%action = ("Ending tag in the middle of an attribute")
      else if (c .in. whitespace) then
         fx%state = SPACE_BEFORE_EQUAL  
         if (fx%debug) fx%action = ("Whitespace after attr. name (specs?)")
         call add_key_to_dict(fx%attributes, str(fx%buffer))
         call reset_buffer(fx%buffer)
      else if ( c == "=" ) then
         fx%state = EQUAL
         if (fx%debug) fx%action = ("End of attr. name")
         call add_key_to_dict(fx%attributes, str(fx%buffer))
         call reset_buffer(fx%buffer)
      else if (c .in. NameChars) then
         if (fx%debug) fx%action = ("Reading attribute name chars")
         call add_to_buffer(c,fx%buffer)
      else
         fx%state = ERROR
         fx%action = ("Illegal character for attribute name")
      endif

 case (EQUAL)
      if ( (c == """") .or. (c == "'") ) then
         fx%state = START_QUOTE
         if (fx%debug) fx%action = ("Found beginning quote")
         fx%quote_char = c
      else if (c .in. whitespace) then
         fx%state = SPACE_AFTER_EQUAL
         if (fx%debug) fx%action = ("Whitespace after equal sign...")
      else
         fx%state = ERROR
         fx%action = ("Must use quotes for attribute values")
      endif

 case (SPACE_BEFORE_EQUAL)
      if ( c == "=" ) then
         fx%state = EQUAL
         if (fx%debug) fx%action = ("Equal sign")
      else if (c .in. whitespace) then
         if (fx%debug) fx%action = ("More whitespace before equal sign...")
      else
         fx%state = ERROR
         fx%action = ("Must use equal sign for attribute values")
      endif

 case (SPACE_AFTER_EQUAL)
      if ( c == "=" ) then
         fx%state = ERROR
         fx%action = ("Duplicate Equal sign")
      else if (c .in. whitespace) then
         if (fx%debug) fx%action = ("More whitespace after equal sign...")
      else  if ( (c == """") .or. (c == "'") ) then
         fx%state = START_QUOTE
         fx%quote_char = c
         if (fx%debug) fx%action = ("Found beginning quote")
      else
         fx%state = ERROR
         fx%action = ("Must use quotes for attribute values")
      endif

 case (START_QUOTE)
      if (c == fx%quote_char) then
         fx%state = END_QUOTE
         if (fx%debug) fx%action = ("Emtpy attribute value...")
         if (fx%entities_in_attributes) then
            call add_value_to_dict(fx%attributes, &
                 entity_filter_text(fx%entities, str(fx%buffer)))
            fx%entities_in_attributes = .false.
         else
            call add_value_to_dict(fx%attributes, str(fx%buffer))
         endif
         call reset_buffer(fx%buffer)
      else if (c == "<") then
         fx%state = ERROR
         fx%action = ("Attribute value cannot contain <")
      else   ! actually allowed chars in att values... Specs: No "<"        
         fx%state = IN_ATT_VALUE
         if (fx%debug) fx%action = ("Starting to read attribute value")
         if (c == "&") fx%entities_in_attributes = .true.
         call add_to_buffer(c,fx%buffer)
      endif

 case (IN_ATT_VALUE)
      if (c == fx%quote_char) then
         fx%state = END_QUOTE
         if (fx%debug) fx%action = ("End of attribute value")
         if (fx%entities_in_attributes) then
            call add_value_to_dict(fx%attributes, &
                 entity_filter_text(fx%entities, str(fx%buffer)))
            fx%entities_in_attributes = .false.
         else
            call add_value_to_dict(fx%attributes, str(fx%buffer))
         endif
         call reset_buffer(fx%buffer)
      else if (c == "<") then
         fx%state = ERROR
         fx%action = ("Attribute value cannot contain <")
      else if ( (c == char(10)) ) then
         fx%state = ERROR
!
!        Aparently other whitespace is allowed...
!
         fx%action = ("No newline allowed in attr. value (specs?)")
      else        ! all other chars allowed in attr value
         if (fx%debug) fx%action = ("Reading attribute value chars")
         call add_to_buffer(c,fx%buffer)
         if (c == "&") fx%entities_in_attributes = .true.
      endif

 case (END_QUOTE)
      if ((c == """") .or. (c == "'")) then
         fx%state = ERROR
         fx%action = ("Duplicate end quote")
      else if (c .in. whitespace) then
         fx%state = WHITESPACE_IN_TAG
         if (fx%debug) fx%action = ("Space in between attributes or to end of tag")
      else if (c == "<") then
         fx%state = ERROR
         fx%action = ("Starting tag within tag")
      else if (c == ">") then
         if (fx%context == PI_TAG) then
            fx%state = ERROR
            fx%action = "End of Processing Instruction without ?"
         else
            fx%state = END_TAG_MARKER
            signal  = END_OF_TAG
            if (fx%debug) fx%action = ("Ending tag after some attributes")
         endif
      else if (c == "/") then
         if (fx%context /= OPENING_TAG) then
            fx%state = ERROR
            fx%action = ("Single tag did not open as start tag")
         else 
            fx%state = SINGLETAG_MARKER
            fx%context = SINGLE_TAG
            if (fx%debug) fx%action = ("Almost ending single tag after some attributes")
         endif
      else   
         fx%state = ERROR
         fx%action = ("Must have some whitespace after att. value")
      endif


 case (WHITESPACE_IN_TAG)
      if ( c .in. whitespace) then
         if (fx%debug) fx%action = ("Reading whitespace in tag")
      else if (c == "<") then
         fx%state = ERROR
         fx%action = ("Starting tag within tag")
      else if (c == ">") then
         if (fx%context == PI_TAG) then
            fx%state = ERROR
            fx%action = "End of XML declaration without ?"
         else
            fx%state = END_TAG_MARKER
            signal  = END_OF_TAG
            if (fx%debug) fx%action = ("End whitespace in tag")
         endif
      else if (c == "/") then
         if (fx%context /= OPENING_TAG) then
            fx%state = ERROR
            fx%action = ("Single tag did not open as start tag")
         else 
            fx%state = SINGLETAG_MARKER
            fx%context = SINGLE_TAG
            if (fx%debug) fx%action = ("End whitespace in single tag")
         endif
      else if (c .in. initialNameChars) then
         fx%state = IN_ATT_NAME
         if (fx%debug) fx%action = ("Starting Attribute name in tag")
         call add_to_buffer(c,fx%buffer)
      else
         fx%state = ERROR
         fx%action = ("Illegal initial character for attribute")
      endif

 case (QUESTION_MARK_IN_TARGET)
   if (c == ">") then
     fx%state = END_TAG_MARKER
     signal  = END_OF_TAG
     if (associated(fx%element_name)) deallocate(fx%element_name)
     allocate(fx%element_name(len(fx%buffer)))
     fx%element_name = buffer_to_chararray(fx%buffer)
     if (associated(fx%pcdata)) deallocate(fx%pcdata)
     allocate(fx%pcdata(0))
     if (fx%debug) fx%action = ("End of PI")
   else
     fx%state = ERROR
     fx%action = ("Badly terminated PI")
   endif

 case (QUESTION_MARK_IN_CONTENT)
   if (c == ">") then
     fx%state = END_TAG_MARKER
     signal  = END_OF_TAG
     if (associated(fx%pcdata)) deallocate(fx%pcdata)
     allocate(fx%pcdata(len(fx%buffer)))
     fx%pcdata = buffer_to_chararray(fx%buffer)
     if (fx%debug) fx%action = ("End of PI")
   else
     fx%state = IN_PI_CONTENT
     call add_to_buffer(c, fx%buffer)
   endif

 case (IN_COMMENT)
      !
      ! End of comment is  "-->", and  ">" can appear inside comments
      !
      if (c == "-") then
         fx%state = ONE_HYPHEN
         if (fx%debug) fx%action = ("Saw - in Comment")
      else
         if (fx%debug) fx%action = ("Reading comment")
         call add_to_buffer(c,fx%buffer)
      endif

 case (ONE_HYPHEN)
      if (c == "-") then
         fx%state = TWO_HYPHEN
         if (fx%debug) fx%action = ("About to end comment")
      else
         fx%state = IN_COMMENT
         if (fx%debug) fx%action = ("Keep reading comment after -: ")
         call add_to_buffer("-",fx%buffer)
         call add_to_buffer(c,fx%buffer)
      endif

 case (TWO_HYPHEN)
      if (c == ">") then
         fx%state = END_TAG_MARKER
         signal  = END_OF_TAG
         if (fx%debug) fx%action = ("End of Comment")
         allocate(fx%pcdata(len(fx%buffer)))
         fx%pcdata = buffer_to_chararray(fx%buffer)
                ! Same behavior as pcdata
         call reset_buffer(fx%buffer)
      else
         fx%state = ERROR
         fx%action = ("Cannot have -- in comment")
      endif

 case (SINGLETAG_MARKER)

      if (c == ">") then
         fx%state = END_TAG_MARKER
         signal  = END_OF_TAG
         if (fx%debug) fx%action = ("Ending tag")
         ! We have to call begin_element AND end_element
      else 
         fx%state = ERROR
         fx%action = ("Wrong ending of single tag")
      endif

 case (IN_PCDATA)
      if (c == "<") then
         fx%state = START_TAG_MARKER
         signal = CHUNK_OF_PCDATA
         if (fx%debug) fx%action = ("End of pcdata -- Starting tag")
         if (fx%entities_in_pcdata) then
            allocate(fx%pcdata(entity_filter_text_len(fx%entities, str(fx%buffer))))
            fx%pcdata = vs_str(entity_filter_text(fx%entities, str(fx%buffer)))
            fx%entities_in_pcdata = .false.
         else
            allocate(fx%pcdata(len(fx%buffer)))
            fx%pcdata = buffer_to_chararray(fx%buffer)
         endif
         call reset_buffer(fx%buffer)
      else if (c == ">") then
         fx%state = ERROR
         fx%action = ("Ending tag without starting it!")
      else if  (c == char(10)) then
         fx%state = IN_PCDATA_AT_EOL
         signal = CHUNK_OF_PCDATA
         if (fx%debug) fx%action = ("Resetting PCDATA buffer at newline")
         call add_to_buffer(c,fx%buffer)
         if (fx%entities_in_pcdata) then
            allocate(fx%pcdata(entity_filter_text_len(fx%entities, str(fx%buffer))))
            fx%pcdata = vs_str(entity_filter_text(fx%entities, str(fx%buffer)))
            fx%entities_in_pcdata = .false.
         else
            allocate(fx%pcdata(len(fx%buffer)))
            fx%pcdata = buffer_to_chararray(fx%buffer)
         endif
         call reset_buffer(fx%buffer)
      else
         call add_to_buffer(c,fx%buffer)
         if (c=="&") fx%entities_in_pcdata = .true.
         !FIXME actually we should replace and reparse at this point.
         !NOt yet clear to me whether contents need fully reparsed or not though
         !If there is an ampersand in the replaced text, what happens to it?
         if (fx%debug) fx%action = ("Reading pcdata")
         !
         ! Check whether we are close to the end of the buffer. 
         ! If so, make a chunk and reset the buffer
         if (c .in. whitespace) then
            if (buffer_nearly_full(fx%buffer)) then
               signal = CHUNK_OF_PCDATA
               if (fx%debug) fx%action = ("Resetting almost full PCDATA buffer")
               if (fx%entities_in_pcdata) then
                 allocate(fx%pcdata(entity_filter_text_len(fx%entities, str(fx%buffer))))
                 fx%pcdata = vs_str(entity_filter_text(fx%entities, str(fx%buffer)))
                 fx%entities_in_pcdata = .false.
               else
                  allocate(fx%pcdata(len(fx%buffer)))
                  fx%pcdata = buffer_to_chararray(fx%buffer)
               endif
               call reset_buffer(fx%buffer)
            endif
         endif
      endif

 case (IN_PCDATA_AT_EOL)
      !
      ! Avoid triggering an extra pcdata event
      !
      if (c == "<") then
         fx%state = START_TAG_MARKER
         if (fx%debug) fx%action = ("No more pcdata after eol-- Starting tag")
      else if (c == ">") then
         fx%state = ERROR
         fx%action = ("Ending tag without starting it!")
      else if  (c == char(10)) then
         fx%state = IN_PCDATA_AT_EOL
         signal = CHUNK_OF_PCDATA
         if (fx%debug) fx%action = ("Resetting PCDATA buffer at repeated newline")
         call add_to_buffer(c,fx%buffer)
         if (fx%entities_in_pcdata) then
            allocate(fx%pcdata(entity_filter_text_len(fx%entities, str(fx%buffer))))
            fx%pcdata = vs_str(entity_filter_text(fx%entities, str(fx%buffer)))
            fx%entities_in_pcdata = .false.
         else
            allocate(fx%pcdata(len(fx%buffer)))
            fx%pcdata = buffer_to_chararray(fx%buffer)
         endif
         call reset_buffer(fx%buffer)
      else
         fx%state = IN_PCDATA
         call add_to_buffer(c,fx%buffer)
         if (c=="&")  fx%entities_in_pcdata = .true.
         if (fx%debug) fx%action = ("Resuming reading pcdata after EOL")
         !
         ! Check whether we are close to the end of the buffer. 
         ! If so, make a chunk and reset the buffer
         if (c .in. whitespace) then
            if (buffer_nearly_full(fx%buffer)) then
               signal = CHUNK_OF_PCDATA
               if (fx%debug) fx%action = ("Resetting almost full PCDATA buffer")
               if (fx%entities_in_pcdata) then
                  allocate(fx%pcdata(entity_filter_text_len(fx%entities, str(fx%buffer))))
                  fx%pcdata = vs_str(entity_filter_text(fx%entities, str(fx%buffer)))
                  fx%entities_in_pcdata = .false.
               else
                  allocate(fx%pcdata(len(fx%buffer)))
                  fx%pcdata = buffer_to_chararray(fx%buffer)
               endif
               call reset_buffer(fx%buffer)
            endif
         endif
      endif



 case (END_TAG_MARKER)
!
      if (c == "<") then
         fx%state = START_TAG_MARKER
         if (fx%debug) fx%action = ("Starting tag")
      else if (c == ">") then
         fx%state = ERROR
         fx%action = ("Double ending of tag!")
!
!     We should make this whitespace in general (maybe not?
!     how about indentation in text chunks?)
!     See specs.
!
      else if (c == char(10)) then
        ! Ignoring LF after end of tag is probably non standard...

         if (fx%debug) &
            fx%action = ("---------Discarding newline after end of tag")

        !!!  New code for full compliance
        ! fx%state = IN_PCDATA_AT_EOL
        ! call add_to_buffer(c,fx%buffer)
        ! if (fx%debug) &
        !    fx%action = ("Found LF after end of tag. Emitting PCDATA event")
        ! signal = CHUNK_OF_PCDATA
        ! if (fx%entities_in_pcdata) then
        !    call entity_filter(fx%buffer,fx%pcdata)
        !    fx%entities_in_pcdata = .false.
        ! else
        !    fx%pcdata = fx%buffer
        ! endif
        ! call reset_buffer(fx%buffer)
      else
         fx%state = IN_PCDATA
         call add_to_buffer(c,fx%buffer)
         if (c=="&") fx%entities_in_pcdata = .true.
         if (fx%debug) fx%action = ("End of Tag. Starting to read PCDATA")
      endif

 case (IN_PI_TARGET)
   if (c == '?') then
     fx%state = QUESTION_MARK_IN_TARGET
     if (fx%debug) fx%action = ("About to end PI")
   elseif (c .in. nameChars) then
     call add_to_buffer(c, fx%buffer)
     if (fx%debug) fx%action = ("Reading name chars in PI target")
   elseif (c.in.whitespace) then
     if (associated(fx%element_name)) deallocate(fx%element_name)
     allocate(fx%element_name(len(fx%buffer)))
     fx%element_name = buffer_to_chararray(fx%buffer)
     fx%action = ("Finished reading PI target")
     fx%state = IN_PI_WHITESPACE
   else
     fx%state = ERROR
     fx%action = ("Illegal character in PI target")
   endif

 case (IN_PI_WHITESPACE)
   if (c .in .whitespace) then
     continue ! Not sure if this is correct ...
   elseif (c == '?') then
     fx%state = QUESTION_MARK_IN_CONTENT
     if (fx%debug) fx%action = ("Maybe about to end PI")
   else
     fx%state = IN_PI_CONTENT
     call reset_buffer(fx%buffer)
     call add_to_buffer(c, fx%buffer)
     if (fx%debug) fx%action = ("Reading chars for PI content")
   endif

 case (IN_PI_CONTENT)
   if (c == '?') then
     fx%state = QUESTION_MARK_IN_CONTENT
     if (fx%debug) fx%action = ("Maybe about to end PI")
   else
     fx%state = IN_PI_CONTENT
     call add_to_buffer(c, fx%buffer)
     if (fx%debug) fx%action = ("Reading chars for PI content")
   endif


 case (ERROR)

    call FoX_error("Cannot continue after parsing errors!")

 end select

if (fx%state == ERROR) signal  = EXCEPTION

end subroutine evolve_fsm

end module m_sax_fsm
