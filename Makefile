# .DELETE_ON_ERROR:
.SECONDARY:
.PHONY: clean all setup
.DEFAULT: all

container_cmd ?= docker
# container_args ?= -w /board -v $(shell pwd):/board --rm
container_args ?= --platform=linux/amd64 -w /board -v $(shell pwd):/board --rm
kikit ?= yaqwsx/kikit:v1.3.0
freerouting ?= ghcr.io/hedefalk/freerouting-x11:v1.8.0
kicad-automation-scripts ?= soundmonster/kicad-automation-scripts
# soundmonster published this https://github.com/productize/kicad-automation-scripts

setup:
	npm install

# Generate kicad_pcb natively
output/pcbs/board.kicad_pcb output/pcbs/top_plate.kicad_pcb output/pcbs/bottom_plate.kicad_pcb &: config.yaml
	npm run gen

# output dsn from kicad_pcb for routing input
output/pcbs/%.dsn: output/pcbs/%.kicad_pcb
	# file can not be present or the script will refuse to run
	if [ -f "$@" ] ; then rm $@ ; fi
	${container_cmd} run ${container_args} ${kicad-automation-scripts} /usr/lib/python2.7/dist-packages/kicad-automation/pcbnew_automation/export_dsn.py $< $@

# route dsn to ses
output/routed_pcbs/%.ses: output/pcbs/%.dsn
	mkdir -p $(shell dirname $@)
	${container_cmd} run ${container_args} ${freerouting} -de $< -do $@ -mp 10

# import ses to kicad_pcb
output/routed_pcbs/%.kicad_pcb: output/routed_pcbs/%.ses output/pcbs/%.kicad_pcb
	mkdir -p $(shell dirname $@)
	# file can not be present or the script will refuse to run
	if [ -f "$@" ] ; then rm $@ ; fi
	${container_cmd} run ${container_args} ${kicad-automation-scripts} /usr/lib/python2.7/dist-packages/kicad-automation/pcbnew_automation/import_ses.py output/pcbs/$*.kicad_pcb $< --output-file $@

# run drc
output/routed_pcbs/%-drc/: output/routed_pcbs/%.kicad_pcb
	mkdir -p $@
	${container_cmd} run ${container_args} ${kicad-automation-scripts} /usr/lib/python2.7/dist-packages/kicad-automation/pcbnew_automation/run_drc.py  $< $@

# plot pngs
output/routed_pcbs/%-front.png: output/routed_pcbs/%.kicad_pcb
	mkdir -p $(shell dirname $@)
	${container_cmd} run --entrypoint pcbdraw ${container_args} ${kikit} plot --style oshpark-afterdark.json $< $@

output/routed_pcbs/%-back.png: output/routed_pcbs/%.kicad_pcb
	mkdir -p $(shell dirname $@)
	${container_cmd} run --entrypoint pcbdraw ${container_args} ${kikit} plot --side back --style oshpark-afterdark.json $< $@

# generate gerbers
output/gerbers/%/gerbers.zip: output/routed_pcbs/%.kicad_pcb
	mkdir -p $(shell dirname $@)
	${container_cmd} run ${container_args} ${kikit} fab jlcpcb --no-drc --no-assembly $< $(shell dirname $@)

clean:
	rm -rf output

all: \
	output/routed_pcbs/board-front.png \
	output/routed_pcbs/board-back.png \
	output/gerbers/top_plate/gerbers.zip \
	output/gerbers/bottom_plate/gerbers.zip \
	output/gerbers/board/gerbers.zip


