function onLoad(saved_data)
	if saved_data~='' then
		deckDir=tonumber(saved_data)
	else
		deckDir=-1
	end
	if deckDir==1 then
		lab='→'
		tip='card extraction: [b]right[/b]'
	else
		lab='←'
		tip='card extraction: [b]left[/b]'
	end
	self.createButton({
		label=lab,
		tooltip=tip,
		click_function="changeDeckDir",
		function_owner=self,
		position={-1.6,0.1,-1.3},
		height=200,
		width=400,
		font_size=500,
		font_color={1,1,1,90},
		color={0,0,0,0},
		})
end
function changeDeckDir()
	deckDir=deckDir*-1
	if deckDir==1 then
		lab='→'
		tip='card extraction: [b]right[/b]'
	else
		lab='←'
		tip='card extraction: [b]left[/b]'
	end
	self.editButton({index=0,label=lab,tooltip=tip})
  self.script_state = deckDir
end

function onCollisionEnter(co)
	nowt=os.time()
	if prevt==nil then prevt=0 end
	if nowt-prevt<1 then return end
	prevt=nowt
	deck = co.collision_object
	if deck.type == "Deck" then
    desc=self.getDescription()
    nTake=desc:match('%d+')
    if nTake==nil then nTake=1 end
    desc=desc:gsub('%d',''):gsub('%p','')
    searchTerm=desc
    if searchTerm==nil then searchTerm='' end
    nTaken=0

    for i,card in ipairs(deck.getObjects()) do
      cname=card.name:lower():gsub('%p','')
      if cname:match('basic') and cname:match('land') and cname:match(searchTerm) then
        nTaken=nTaken+1
        rot=deck.getRotation()
        pos=deck.getPosition()
        rig=deck.getTransformRight()
        rot[3]=0
        pos=pos+rig:scale(deckDir*2.4+deckDir*(nTaken-1)*1.5)
        pos[2]=pos[2]+nTaken*0.1
        deck.takeObject({index=i-nTaken,position=pos,rotation=rot})
        if nTaken==tonumber(nTake) then
          break
        end
      end
    end
    Wait.time(function() deck.shuffle() end, 0.1, 5)
    self.destruct()
	end
end