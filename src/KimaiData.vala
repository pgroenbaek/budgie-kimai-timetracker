/*
 * This file is part of the Budgie Desktop Kimai Timetracker Applet.
 *
 * Copyright (C) 2025 Peter Grønbæk Andersen <peter@grnbk.io>
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

using GLib;

public class KimaiCustomer : GLib.Object {
    public int id { get; set; }
    public string name { get; set; }
}

public class KimaiProject : GLib.Object {
    public int id { get; set; }
    public string name { get; set; }
    public KimaiCustomer? customer { get; set; }
}

public class KimaiActivity : GLib.Object {
    public int id { get; set; }
    public string name { get; set; }
}

public class KimaiTimesheet : GLib.Object {
    public int id { get; set; }
    public string description { get; set; }
    public DateTime begin { get; set; }
    public DateTime? end { get; set; }
    public KimaiProject project { get; set; }
    public KimaiActivity activity { get; set; }
}