# latte-okna: make → latte-okna.so (proti nainštalovanému hyprland-devel, ako hyprbars)
CXXFLAGS ?= -O2
CXXFLAGS += -shared -fPIC -std=c++2b -Wno-c++11-narrowing --no-gnu-unique
INCLUDES = `pkg-config --cflags pixman-1 libdrm hyprland libinput libudev wayland-server xkbcommon`

latte-okna.so: main.cpp
	$(CXX) $(CXXFLAGS) $(INCLUDES) $^ -o $@

clean:
	rm -f latte-okna.so
